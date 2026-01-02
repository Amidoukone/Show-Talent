import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// État minimal pour une session de téléversement résumable.
class UploadSessionState {
  final String sessionId;
  final String uploadUrl;
  final DateTime expiresAt;
  final String videoPath;
  final String thumbnailPath;
  final String localFilePath;
  final int uploadedBytes;

  const UploadSessionState({
    required this.sessionId,
    required this.uploadUrl,
    required this.expiresAt,
    required this.videoPath,
    required this.thumbnailPath,
    required this.localFilePath,
    this.uploadedBytes = 0,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  UploadSessionState copyWith({
    String? uploadUrl,
    DateTime? expiresAt,
    int? uploadedBytes,
  }) {
    return UploadSessionState(
      sessionId: sessionId,
      uploadUrl: uploadUrl ?? this.uploadUrl,
      expiresAt: expiresAt ?? this.expiresAt,
      videoPath: videoPath,
      thumbnailPath: thumbnailPath,
      localFilePath: localFilePath,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'uploadUrl': uploadUrl,
      'expiresAt': expiresAt.toIso8601String(),
      'videoPath': videoPath,
      'thumbnailPath': thumbnailPath,
      'localFilePath': localFilePath,
      'uploadedBytes': uploadedBytes,
    };
  }

  factory UploadSessionState.fromJson(Map<String, dynamic> json) {
    return UploadSessionState(
      sessionId: json['sessionId'] as String,
      uploadUrl: json['uploadUrl'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      videoPath: json['videoPath'] as String,
      thumbnailPath: json['thumbnailPath'] as String,
      localFilePath: json['localFilePath'] as String,
      uploadedBytes: (json['uploadedBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Client dédié à la récupération des URLs signées + téléversement résumable.
class UploadClient {
  static const _region = 'europe-west1';
  static const _chunkSize = 1024 * 1024; // 1 Mo
  static const _sessionCacheFile = 'upload_session.json';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      followRedirects: false,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: _region);

  UploadSessionState? _cachedSession;

  Future<String> _cachePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_sessionCacheFile';
  }

  Future<UploadSessionState?> loadPersistedSession() async {
    if (_cachedSession != null) return _cachedSession;

    try {
      final path = await _cachePath();
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      _cachedSession = UploadSessionState.fromJson(data);
      return _cachedSession;
    } catch (_) {
      return null;
    }
  }

  Future<void> persistSession(UploadSessionState session) async {
    _cachedSession = session;
    try {
      final path = await _cachePath();
      final file = File(path);
      await file.writeAsString(jsonEncode(session.toJson()));
    } catch (_) {}
  }

  Future<void> clearPersistedSession() async {
    _cachedSession = null;
    try {
      final path = await _cachePath();
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<UploadSessionState> ensureSession({
    required String localFilePath,
    String contentType = 'video/mp4',
  }) async {
    final persisted = await loadPersistedSession();
    if (persisted != null && persisted.localFilePath == localFilePath) {
      if (persisted.isExpired) {
        return refreshSession(persisted);
      }
      return persisted;
    }
    return _createSession(localFilePath: localFilePath, contentType: contentType);
  }

  Future<UploadSessionState> _createSession({
    required String localFilePath,
    String? sessionId,
    String contentType = 'video/mp4',
  }) async {
    final callable = _functions.httpsCallable('createUploadSession');
    final result = await callable.call<Map<String, dynamic>>({
      if (sessionId != null) 'sessionId': sessionId,
      'contentType': contentType,
    });

    final data = result.data;
    final expiresAtMs = (data['expiresAt'] as num?)?.toInt() ?? 0;
    final session = UploadSessionState(
      sessionId: data['sessionId'] as String,
      uploadUrl: data['uploadUrl'] as String,
      videoPath: data['videoPath'] as String,
      thumbnailPath: data['thumbnailPath'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
      localFilePath: localFilePath,
      uploadedBytes: 0,
    );
    await persistSession(session);
    return session;
  }

  Future<UploadSessionState> refreshSession(
    UploadSessionState session, {
    int? uploadedBytes,
  }) async {
    final refreshed = await _createSession(
      localFilePath: session.localFilePath,
      sessionId: session.sessionId,
    );
    return refreshed.copyWith(
      uploadedBytes: uploadedBytes ?? session.uploadedBytes,
    );
  }

  int _extractLastByte(String? rangeHeader) {
    if (rangeHeader == null) return -1;
    final match = RegExp(r'bytes=0-(\d+)').firstMatch(rangeHeader);
    if (match == null) return -1;
    return int.tryParse(match.group(1) ?? '') ?? -1;
  }

  Future<int> _queryRemoteOffset(
    UploadSessionState session,
    int totalBytes,
  ) async {
    try {
      final response = await _dio.put<Object?>(
        session.uploadUrl,
        data: Stream<List<int>>.empty(),
        options: Options(
          headers: {
            'Content-Length': '0',
            'Content-Range': 'bytes */$totalBytes',
            'Content-Type': 'application/octet-stream',
          },
        ),
      );
      if (response.statusCode == 308) {
        return _extractLastByte(response.headers.value('range'));
      }
    } catch (_) {}
    return -1;
  }

  Future<bool> uploadFile({
    required UploadSessionState session,
    required File file,
    required void Function(double) onProgress,
    CancelToken? cancelToken,
    void Function()? onUrlRefreshed,
  }) async {
    var current = session;
    final totalBytes = await file.length();
    var uploadedBytes = session.uploadedBytes;

    final remoteOffset = await _queryRemoteOffset(current, totalBytes);
    if (remoteOffset >= 0) {
      uploadedBytes = remoteOffset + 1;
    }

    onProgress(totalBytes == 0 ? 0 : uploadedBytes / totalBytes);

    while (uploadedBytes < totalBytes) {
      if (current.isExpired) {
        current = await refreshSession(current, uploadedBytes: uploadedBytes);
        onUrlRefreshed?.call();
        final refreshedOffset = await _queryRemoteOffset(current, totalBytes);
        uploadedBytes = refreshedOffset >= 0 ? refreshedOffset + 1 : 0;
      }

      final end = (uploadedBytes + _chunkSize - 1).clamp(0, totalBytes - 1);
      // ignore: unnecessary_type_check
      final chunkEnd = end is int ? end : (end as num).toInt();
      final length = (chunkEnd - uploadedBytes + 1);

      try {
        final response = await _dio.put<Object?>(
          current.uploadUrl,
          data: file.openRead(uploadedBytes, chunkEnd + 1),
          options: Options(
            headers: {
              'Content-Length': '$length',
              'Content-Range': 'bytes $uploadedBytes-$chunkEnd/$totalBytes',
              'Content-Type': 'video/mp4',
            },
          ),
          cancelToken: cancelToken,
        );

        if (response.statusCode == 308) {
          final lastByte = _extractLastByte(response.headers.value('range'));
          if (lastByte >= 0) {
            uploadedBytes = lastByte + 1;
          } else {
            uploadedBytes = chunkEnd + 1;
          }
        } else if (response.statusCode == 200 || response.statusCode == 201) {
          uploadedBytes = totalBytes;
        } else {
          await Future.delayed(const Duration(seconds: 1));
          final remote = await _queryRemoteOffset(current, totalBytes);
          if (remote >= 0) {
            uploadedBytes = remote + 1;
          }
        }
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 750));
        final remote = await _queryRemoteOffset(current, totalBytes);
        if (remote >= 0) {
          uploadedBytes = remote + 1;
        }
      }

      await persistSession(current.copyWith(uploadedBytes: uploadedBytes));
      onProgress(totalBytes == 0 ? 0 : uploadedBytes / totalBytes);
    }

    return true;
  }

  Future<bool> finalizeUpload({
    required String sessionId,
    required Map<String, dynamic> metadata,
  }) async {
    final callable = _functions.httpsCallable('finalizeUpload');
    final result = await callable.call<Map<String, dynamic>>({
      'sessionId': sessionId,
      'metadata': metadata,
    });
    return (result.data['ok'] as bool?) ?? false;
  }
}