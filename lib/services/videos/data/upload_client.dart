import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// ---------------------------------------------------------------------------
/// État minimal pour une session de téléversement résumable (VIDÉO)
/// ---------------------------------------------------------------------------
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

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'uploadUrl': uploadUrl,
        'expiresAt': expiresAt.toIso8601String(),
        'videoPath': videoPath,
        'thumbnailPath': thumbnailPath,
        'localFilePath': localFilePath,
        'uploadedBytes': uploadedBytes,
      };

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

/// ---------------------------------------------------------------------------
/// Ticket sécurisé pour upload de miniature
/// ---------------------------------------------------------------------------
class ThumbnailUploadTicket {
  final String uploadUrl;
  final String thumbnailPath;
  final DateTime expiresAt;
  final int expectedSize;
  final String expectedHash;
  final String contentType;

  const ThumbnailUploadTicket({
    required this.uploadUrl,
    required this.thumbnailPath,
    required this.expiresAt,
    required this.expectedSize,
    required this.expectedHash,
    required this.contentType,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// ---------------------------------------------------------------------------
/// Client d’upload vidéo + miniature (résumable, robuste)
/// ---------------------------------------------------------------------------
class UploadClient {
  static const _region = 'europe-west1';

  static const _chunkSize = 1024 * 1024; // 1 Mo (vidéo)
  static const _thumbnailChunkSize = 512 * 1024; // 512 Ko (miniature)
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

  // ---------------------------------------------------------------------------
  // Session persistence
  // ---------------------------------------------------------------------------

  Future<String> _cachePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_sessionCacheFile';
  }

  Future<UploadSessionState?> loadPersistedSession() async {
    if (_cachedSession != null) return _cachedSession;

    try {
      final file = File(await _cachePath());
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      _cachedSession = UploadSessionState.fromJson(data);
      return _cachedSession;
    } catch (_) {
      return null;
    }
  }

  Future<void> persistSession(UploadSessionState session) async {
    _cachedSession = session;
    try {
      final file = File(await _cachePath());
      await file.writeAsString(jsonEncode(session.toJson()));
    } catch (_) {}
  }

  Future<void> clearPersistedSession() async {
    _cachedSession = null;
    try {
      final file = File(await _cachePath());
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Session création / refresh
  // ---------------------------------------------------------------------------

  Future<UploadSessionState> ensureSession({
    required String localFilePath,
    String contentType = 'video/mp4',
  }) async {
    final persisted = await loadPersistedSession();
    if (persisted != null && persisted.localFilePath == localFilePath) {
      return persisted.isExpired ? refreshSession(persisted) : persisted;
    }
    return _createSession(
        localFilePath: localFilePath, contentType: contentType);
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
      sessionId: data['sessionId'],
      uploadUrl: data['uploadUrl'],
      videoPath: data['videoPath'],
      thumbnailPath: data['thumbnailPath'],
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
      localFilePath: localFilePath,
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
    return refreshed.copyWith(uploadedBytes: uploadedBytes);
  }

  // ---------------------------------------------------------------------------
  // Upload vidéo résumable (INCHANGÉ)
  // ---------------------------------------------------------------------------

  int _extractLastByte(String? rangeHeader) {
    final match = RegExp(r'bytes=0-(\d+)').firstMatch(rangeHeader ?? '');
    return match != null ? int.parse(match.group(1)!) : -1;
  }

  Future<int> _queryRemoteOffset(
    UploadSessionState session,
    int totalBytes,
  ) async {
    try {
      final response = await _dio.put(
        session.uploadUrl,
        data: Stream<List<int>>.empty(),
        options: Options(headers: {
          'Content-Length': '0',
          'Content-Range': 'bytes */$totalBytes',
          'Content-Type': 'application/octet-stream',
        }),
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
    if (remoteOffset >= 0) uploadedBytes = remoteOffset + 1;

    while (uploadedBytes < totalBytes) {
      if (current.isExpired) {
        current = await refreshSession(current, uploadedBytes: uploadedBytes);
        onUrlRefreshed?.call();
      }

      final end = (uploadedBytes + _chunkSize - 1).clamp(0, totalBytes - 1);
      final length = end - uploadedBytes + 1;

      try {
        final response = await _dio.put(
          current.uploadUrl,
          data: file.openRead(uploadedBytes, end + 1),
          options: Options(headers: {
            'Content-Length': '$length',
            'Content-Range': 'bytes $uploadedBytes-$end/$totalBytes',
            'Content-Type': 'video/mp4',
          }),
          cancelToken: cancelToken,
        );

        if (response.statusCode == 308) {
          uploadedBytes = _extractLastByte(response.headers.value('range')) + 1;
        } else {
          uploadedBytes = totalBytes;
        }
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 750));
      }

      await persistSession(current.copyWith(uploadedBytes: uploadedBytes));
      onProgress(uploadedBytes / totalBytes);
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // Miniature sécurisée (NOUVEAU)
  // ---------------------------------------------------------------------------

  Future<ThumbnailUploadTicket> requestThumbnailTicket({
    required String sessionId,
    required File file,
    required String contentType,
    String? thumbnailPath,
  }) async {
    final size = await file.length();
    final hash = await _computeMd5(file);

    final callable = _functions.httpsCallable('requestThumbnailUploadUrl');
    final result = await callable.call<Map<String, dynamic>>({
      'sessionId': sessionId,
      'hash': hash,
      'size': size,
      'contentType': contentType,
      if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
    });

    final data = result.data;
    return ThumbnailUploadTicket(
      uploadUrl: data['uploadUrl'],
      thumbnailPath: data['thumbnailPath'],
      expiresAt: DateTime.fromMillisecondsSinceEpoch(data['expiresAt']),
      expectedHash: hash,
      expectedSize: size,
      contentType: contentType,
    );
  }

  Future<bool> uploadThumbnailFile({
    required ThumbnailUploadTicket ticket,
    required File file,
    required void Function(double) onProgress,
    CancelToken? cancelToken,
  }) async {
    if (ticket.isExpired) throw Exception('Lien miniature expiré');

    final totalBytes = await file.length();
    var uploadedBytes = 0;

    while (uploadedBytes < totalBytes) {
      final end =
          (uploadedBytes + _thumbnailChunkSize - 1).clamp(0, totalBytes - 1);
      final length = end - uploadedBytes + 1;

      try {
        final response = await _dio.put(
          ticket.uploadUrl,
          data: file.openRead(uploadedBytes, end + 1),
          options: Options(headers: {
            'Content-Length': '$length',
            'Content-Range': 'bytes $uploadedBytes-$end/$totalBytes',
            'Content-Type': ticket.contentType,
          }),
          cancelToken: cancelToken,
        );

        if (response.statusCode == 308) {
          uploadedBytes = _extractLastByte(response.headers.value('range')) + 1;
        } else {
          uploadedBytes = totalBytes;
        }
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 500));
      }

      onProgress(uploadedBytes / totalBytes);
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // Utils
  // ---------------------------------------------------------------------------

  Future<String> _computeMd5(File file) async {
    final bytes = await file.readAsBytes();
    final digest = md5.convert(bytes);
    return digest.toString();
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
