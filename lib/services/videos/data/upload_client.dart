import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

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

class UploadClientException implements Exception {
  final String message;
  final int? statusCode;

  const UploadClientException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

abstract class UploadHttpClient {
  Future<Response<dynamic>> put(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  });
}

class DioUploadHttpClient implements UploadHttpClient {
  DioUploadHttpClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 20),
                followRedirects: false,
                validateStatus: (status) => status != null && status < 500,
              ),
            );

  final Dio _dio;

  @override
  Future<Response<dynamic>> put(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.put<dynamic>(
      path,
      data: data,
      options: options,
      cancelToken: cancelToken,
    );
  }
}

class UploadClient {
  static const _region = 'europe-west1';
  static const _chunkSize = 1024 * 1024;
  static const _thumbnailChunkSize = 512 * 1024;
  static const _sessionCacheFile = 'upload_session.json';
  static const _defaultMaxChunkRetries = 3;
  static const Set<int> _terminalSuccessStatuses = {200, 201, 204};

  UploadClient({
    UploadHttpClient? httpClient,
    FirebaseFunctions? functions,
    Future<String> Function()? cachePathProvider,
    Duration videoRetryDelay = const Duration(milliseconds: 750),
    Duration thumbnailRetryDelay = const Duration(milliseconds: 500),
    int maxChunkRetries = _defaultMaxChunkRetries,
  })  : _httpClient = httpClient ?? DioUploadHttpClient(),
        _functionsOverride = functions,
        _cachePathProvider = cachePathProvider,
        _videoRetryDelay = videoRetryDelay,
        _thumbnailRetryDelay = thumbnailRetryDelay,
        _maxChunkRetries = maxChunkRetries < 1 ? 1 : maxChunkRetries;

  final UploadHttpClient _httpClient;
  final FirebaseFunctions? _functionsOverride;
  final Future<String> Function()? _cachePathProvider;
  final Duration _videoRetryDelay;
  final Duration _thumbnailRetryDelay;
  final int _maxChunkRetries;

  late final FirebaseFunctions _functions =
      _functionsOverride ?? FirebaseFunctions.instanceFor(region: _region);

  UploadSessionState? _cachedSession;

  Future<String> _cachePath() async {
    final override = _cachePathProvider;
    if (override != null) return override();
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

  Future<UploadSessionState> ensureSession({
    required String localFilePath,
    String contentType = 'video/mp4',
  }) async {
    final persisted = await loadPersistedSession();
    if (persisted != null && persisted.localFilePath == localFilePath) {
      return persisted.isExpired ? refreshSession(persisted) : persisted;
    }
    return _createSession(
      localFilePath: localFilePath,
      contentType: contentType,
    );
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

  int _extractLastByte(String? rangeHeader) {
    final match = RegExp(r'bytes=0-(\d+)').firstMatch(rangeHeader ?? '');
    return match != null ? int.parse(match.group(1)!) : -1;
  }

  bool _isTerminalSuccessStatus(int? statusCode) {
    return statusCode != null && _terminalSuccessStatuses.contains(statusCode);
  }

  String _describeError(Object error) {
    if (error is UploadClientException) return error.message;
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null) return 'statut HTTP $statusCode';
      return error.message ?? error.toString();
    }
    return error.toString();
  }

  Future<Response<dynamic>> _sendChunkWithRetry({
    required String uploadUrl,
    required Stream<List<int>> Function() dataFactory,
    required Map<String, String> headers,
    required CancelToken? cancelToken,
    required Duration retryDelay,
    required String uploadLabel,
  }) async {
    int? lastStatusCode;

    for (var attempt = 1; attempt <= _maxChunkRetries; attempt++) {
      try {
        final response = await _httpClient.put(
          uploadUrl,
          data: dataFactory(),
          options: Options(headers: headers),
          cancelToken: cancelToken,
        );

        final statusCode = response.statusCode;
        if (statusCode == 308 || _isTerminalSuccessStatus(statusCode)) {
          return response;
        }

        throw UploadClientException(
          'Statut HTTP inattendu pendant l\'upload $uploadLabel: '
          '${statusCode ?? 'null'}.',
          statusCode: statusCode,
        );
      } catch (error) {
        if (cancelToken?.isCancelled == true) rethrow;

        lastStatusCode =
            error is UploadClientException ? error.statusCode : lastStatusCode;

        if (attempt == _maxChunkRetries) {
          throw UploadClientException(
            'Echec upload $uploadLabel apres $_maxChunkRetries tentatives: '
            '${_describeError(error)}.',
            statusCode: lastStatusCode,
          );
        }

        if (retryDelay > Duration.zero) {
          await Future.delayed(retryDelay);
        }
      }
    }

    throw const UploadClientException('Echec upload: tentative introuvable.');
  }

  Future<int> _queryRemoteOffset(
    UploadSessionState session,
    int totalBytes,
  ) async {
    try {
      final response = await _httpClient.put(
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
      if (_isTerminalSuccessStatus(response.statusCode)) {
        return totalBytes - 1;
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

      final chunkStart = uploadedBytes;
      final end = (chunkStart + _chunkSize - 1).clamp(0, totalBytes - 1);
      final length = end - chunkStart + 1;

      final response = await _sendChunkWithRetry(
        uploadUrl: current.uploadUrl,
        dataFactory: () => file.openRead(chunkStart, end + 1),
        headers: {
          'Content-Length': '$length',
          'Content-Range': 'bytes $chunkStart-$end/$totalBytes',
          'Content-Type': 'video/mp4',
        },
        cancelToken: cancelToken,
        retryDelay: _videoRetryDelay,
        uploadLabel: 'video',
      );

      if (response.statusCode == 308) {
        final lastPersistedByte =
            _extractLastByte(response.headers.value('range'));
        if (lastPersistedByte < chunkStart) {
          throw const UploadClientException(
            'Reponse 308 invalide pendant l\'upload video.',
          );
        }
        uploadedBytes = lastPersistedByte + 1;
      } else {
        uploadedBytes = totalBytes;
      }

      await persistSession(current.copyWith(uploadedBytes: uploadedBytes));
      onProgress(uploadedBytes / totalBytes);
    }

    return true;
  }

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
    if (ticket.isExpired) {
      throw const UploadClientException('Lien miniature expire.');
    }

    final totalBytes = await file.length();
    var uploadedBytes = 0;

    while (uploadedBytes < totalBytes) {
      final chunkStart = uploadedBytes;
      final end =
          (chunkStart + _thumbnailChunkSize - 1).clamp(0, totalBytes - 1);
      final length = end - chunkStart + 1;

      final response = await _sendChunkWithRetry(
        uploadUrl: ticket.uploadUrl,
        dataFactory: () => file.openRead(chunkStart, end + 1),
        headers: {
          'Content-Length': '$length',
          'Content-Range': 'bytes $chunkStart-$end/$totalBytes',
          'Content-Type': ticket.contentType,
        },
        cancelToken: cancelToken,
        retryDelay: _thumbnailRetryDelay,
        uploadLabel: 'miniature',
      );

      if (response.statusCode == 308) {
        final lastPersistedByte =
            _extractLastByte(response.headers.value('range'));
        if (lastPersistedByte < chunkStart) {
          throw const UploadClientException(
            'Reponse 308 invalide pendant l\'upload miniature.',
          );
        }
        uploadedBytes = lastPersistedByte + 1;
      } else {
        uploadedBytes = totalBytes;
      }

      onProgress(uploadedBytes / totalBytes);
    }

    return true;
  }

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
