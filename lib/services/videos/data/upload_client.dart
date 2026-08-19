import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../config/app_environment.dart';
import '../../callable_auth_guard.dart';

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
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 60),
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
  static const _chunkSize = 1024 * 1024;
  static const _thumbnailChunkSize = 512 * 1024;
  static const _sessionCacheFile = 'upload_session.json';
  static const _defaultMaxChunkRetries = 4;
  static const Duration _callableTimeout = Duration(seconds: 75);
  static const Set<int> _terminalSuccessStatuses = {200, 201, 204};

  // Server-side rejections that retrying can never fix -- everything else
  // reaching this layer (timeouts, DNS/connection resets, transient
  // 'unavailable'/'deadline-exceeded'/'internal' Functions errors) is worth
  // a bounded retry so a momentary network blip on createUploadSession,
  // requestThumbnailUploadUrl or finalizeUpload doesn't force the caller to
  // redo the whole prepare+upload flow.
  static const Set<String> _nonRetryableCallableErrorCodes = {
    'permission-denied',
    'invalid-argument',
    'failed-precondition',
    'not-found',
    'already-exists',
    'resource-exhausted',
    'out-of-range',
    'unimplemented',
  };
  static const int _defaultMaxCallableRetries = 3;
  static const Duration _callableRetryBaseDelay = Duration(seconds: 1);

  // The resumable session TTL (server-side, ~45 min) can expire mid-upload
  // on a slow connection, which forces a restart from byte 0 (a new
  // resumable URL means a new server-side upload session). Without a cap,
  // a connection slow enough to never finish within one TTL window would
  // retry this forever with no feedback. 2 refreshes gives a generous
  // multi-hour ceiling before surfacing a clear, actionable error instead.
  static const int _maxSessionRefreshes = 2;

  UploadClient({
    UploadHttpClient? httpClient,
    FirebaseFunctions? functions,
    this._cachePathProvider,
    this._videoRetryDelay = const Duration(milliseconds: 750),
    this._thumbnailRetryDelay = const Duration(milliseconds: 500),
    int maxChunkRetries = _defaultMaxChunkRetries,
    int maxCallableRetries = _defaultMaxCallableRetries,
  }) : _httpClient = httpClient ?? DioUploadHttpClient(),
       _functionsOverride = functions,
       _maxChunkRetries = maxChunkRetries < 1 ? 1 : maxChunkRetries,
       _maxCallableRetries = maxCallableRetries < 1 ? 1 : maxCallableRetries;

  final UploadHttpClient _httpClient;
  final FirebaseFunctions? _functionsOverride;
  final Future<String> Function()? _cachePathProvider;
  final Duration _videoRetryDelay;
  final Duration _thumbnailRetryDelay;
  final int _maxChunkRetries;
  final int _maxCallableRetries;

  /// How long [ensureSession] can legitimately take before it has failed.
  ///
  /// Derived rather than guessed: the caller used to cut session creation off
  /// at a flat 125s while this layer's own budget — [_maxCallableRetries]
  /// attempts of [_callableTimeout] plus linear backoff — ran to nearly twice
  /// that. A cold start that the last retry would have absorbed surfaced as
  /// "Connexion sécurisée trop longue à s'établir" *after* the server had
  /// already created the session, which is the shape of the production
  /// session-creation-timeout failures.
  Duration get sessionCreationBudget {
    var total = _callableTimeout * _maxCallableRetries;
    for (var attempt = 1; attempt < _maxCallableRetries; attempt++) {
      total += _callableRetryBaseDelay * attempt;
    }
    return total + const Duration(seconds: 5);
  }

  late final FirebaseFunctions _functions =
      _functionsOverride ??
      FirebaseFunctions.instanceFor(
        region: AppEnvironmentConfig.functionsRegion,
      );

  UploadSessionState? _cachedSession;

  bool _isRetryableCallableError(Object error) {
    if (error is FirebaseFunctionsException) {
      return !_nonRetryableCallableErrorCodes.contains(error.code);
    }
    // CallableAuthGuard already normalizes server-side rejections into
    // FirebaseFunctionsException; anything else surfacing here is almost
    // always a transport-level failure (timeout, DNS, connection reset),
    // which is worth retrying.
    return true;
  }

  Future<T> _callCallableWithRetry<T>(
    HttpsCallable callable,
    String callableName,
    dynamic parameters,
  ) async {
    for (var attempt = 1; attempt <= _maxCallableRetries; attempt++) {
      try {
        return await CallableAuthGuard.callDataWithHttpFallback<T>(
          callable,
          callableName,
          parameters,
        );
      } catch (error) {
        if (attempt == _maxCallableRetries ||
            !_isRetryableCallableError(error)) {
          rethrow;
        }
        await Future.delayed(_callableRetryBaseDelay * attempt);
      }
    }

    throw UploadClientException('Échec appel $callableName.');
  }

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
    required int fileSizeBytes,
    String contentType = 'video/mp4',
  }) async {
    final persisted = await loadPersistedSession();
    if (persisted != null && persisted.localFilePath == localFilePath) {
      // A reservation (no upload URL yet) and an expired session are the same
      // case here: re-negotiate, reusing the id we already claimed.
      return persisted.isExpired || persisted.uploadUrl.isEmpty
          ? refreshSession(persisted)
          : persisted;
    }
    return _createSession(
      localFilePath: localFilePath,
      fileSizeBytes: fileSizeBytes,
      contentType: contentType,
    );
  }

  /// Records the id this attempt will use *before* asking the server for it.
  ///
  /// createUploadSession is idempotent per sessionId — it merges into the
  /// videos/{sessionId} document rather than creating a new one — but only if
  /// the client can name the same id twice. Letting the server mint the id
  /// meant a lost or timed-out response left the client with nothing to
  /// resume from, so the next attempt created a *second* document stuck at
  /// status "processing" with no Storage object behind it. Those count toward
  /// MAX_CONCURRENT_VIDEO_UPLOADS (2), so two abandoned attempts locked the
  /// user out of uploading for the three hours it takes
  /// reapAbandonedUploadSessions to clear them. Production showed exactly one
  /// such orphan after a session-creation timeout.
  Future<void> _reserveSession(String localFilePath, String sessionId) {
    return persistSession(
      UploadSessionState(
        sessionId: sessionId,
        uploadUrl: '',
        expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
        videoPath: '',
        thumbnailPath: '',
        localFilePath: localFilePath,
      ),
    );
  }

  Future<UploadSessionState> _createSession({
    required String localFilePath,
    required int fileSizeBytes,
    String? sessionId,
    String contentType = 'video/mp4',
  }) async {
    final effectiveSessionId = sessionId ?? const Uuid().v4();
    await _reserveSession(localFilePath, effectiveSessionId);

    final callable = _functions.httpsCallable(
      'createUploadSession',
      options: HttpsCallableOptions(timeout: _callableTimeout),
    );
    final data = await _callCallableWithRetry<Map<String, dynamic>>(
      callable,
      'createUploadSession',
      {
        'sessionId': effectiveSessionId,
        'contentType': contentType,
        'fileSizeBytes': fileSizeBytes,
      },
    );

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

  Future<UploadSessionState> refreshSession(UploadSessionState session) async {
    final file = File(session.localFilePath);
    final fileSizeBytes = await _readValidFileLength(
      file: file,
      label: 'video',
    );
    final refreshed = await _createSession(
      localFilePath: session.localFilePath,
      fileSizeBytes: fileSizeBytes,
      sessionId: session.sessionId,
    );
    // A new resumable URL starts a new server-side upload session.
    return refreshed.copyWith(uploadedBytes: 0);
  }

  int _extractLastByte(String? rangeHeader) {
    final match = RegExp(r'bytes=0-(\d+)').firstMatch(rangeHeader ?? '');
    return match != null ? int.parse(match.group(1)!) : -1;
  }

  bool _isTerminalSuccessStatus(int? statusCode) {
    return statusCode != null && _terminalSuccessStatuses.contains(statusCode);
  }

  int _clampUploadedBytes(int value, int totalBytes) {
    if (value < 0) return 0;
    if (value > totalBytes) return totalBytes;
    return value;
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
          'Statut HTTP inattendu pendant l’upload $uploadLabel: '
          '${statusCode ?? 'null'}.',
          statusCode: statusCode,
        );
      } catch (error) {
        if (cancelToken?.isCancelled == true) rethrow;

        if (error is UploadClientException) {
          lastStatusCode = error.statusCode ?? lastStatusCode;
        } else if (error is DioException) {
          lastStatusCode = error.response?.statusCode ?? lastStatusCode;
        }

        if (attempt == _maxChunkRetries) {
          throw UploadClientException(
            'Échec upload $uploadLabel après $_maxChunkRetries tentatives: '
            '${_describeError(error)}.',
            statusCode: lastStatusCode,
          );
        }

        if (retryDelay > Duration.zero) {
          await Future.delayed(retryDelay);
        }
      }
    }

    throw const UploadClientException('Échec upload : tentative introuvable.');
  }

  Future<int> _queryRemoteOffset(
    UploadSessionState session,
    int totalBytes,
  ) async {
    try {
      final response = await _httpClient.put(
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
      if (_isTerminalSuccessStatus(response.statusCode)) {
        return totalBytes - 1;
      }
    } catch (_) {}
    return -1;
  }

  Future<int> _readValidFileLength({
    required File file,
    required String label,
  }) async {
    if (!await file.exists()) {
      throw UploadClientException('Fichier $label introuvable.');
    }

    final totalBytes = await file.length();
    if (totalBytes <= 0) {
      throw UploadClientException('Fichier $label vide.');
    }

    return totalBytes;
  }

  Future<bool> uploadFile({
    required UploadSessionState session,
    required File file,
    required void Function(double) onProgress,
    CancelToken? cancelToken,
    void Function()? onUrlRefreshed,
  }) async {
    var current = session;
    final totalBytes = await _readValidFileLength(file: file, label: 'video');
    var uploadedBytes = session.uploadedBytes;
    var sessionRefreshCount = 0;

    final remoteOffset = await _queryRemoteOffset(current, totalBytes);
    if (remoteOffset >= 0) {
      uploadedBytes = _clampUploadedBytes(remoteOffset + 1, totalBytes);
    } else if (uploadedBytes < 0 || uploadedBytes >= totalBytes) {
      uploadedBytes = 0;
      await persistSession(current.copyWith(uploadedBytes: 0));
    }

    while (uploadedBytes < totalBytes) {
      if (current.isExpired) {
        if (sessionRefreshCount >= _maxSessionRefreshes) {
          throw const UploadClientException(
            'Le transfert vidéo prend trop de temps sur cette connexion. '
            'Vérifiez votre réseau puis réessayez.',
          );
        }
        sessionRefreshCount++;
        current = await refreshSession(current);
        uploadedBytes = 0;
        await persistSession(current.copyWith(uploadedBytes: 0));
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
        final lastPersistedByte = _extractLastByte(
          response.headers.value('range'),
        );
        if (lastPersistedByte < chunkStart || lastPersistedByte >= totalBytes) {
          throw const UploadClientException(
            'Réponse 308 invalide pendant l’upload vidéo.',
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
    final size = await _readValidFileLength(file: file, label: 'miniature');
    final hash = await _computeMd5(file);

    final callable = _functions.httpsCallable(
      'requestThumbnailUploadUrl',
      options: HttpsCallableOptions(timeout: _callableTimeout),
    );
    final data = await _callCallableWithRetry<Map<String, dynamic>>(
      callable,
      'requestThumbnailUploadUrl',
      {
        'sessionId': sessionId,
        'hash': hash,
        'size': size,
        'contentType': contentType,
        'thumbnailPath': ?thumbnailPath,
      },
    );

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
      throw const UploadClientException('Lien miniature expiré.');
    }

    final totalBytes = await _readValidFileLength(
      file: file,
      label: 'miniature',
    );
    var uploadedBytes = 0;

    while (uploadedBytes < totalBytes) {
      final chunkStart = uploadedBytes;
      final end = (chunkStart + _thumbnailChunkSize - 1).clamp(
        0,
        totalBytes - 1,
      );
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
        final lastPersistedByte = _extractLastByte(
          response.headers.value('range'),
        );
        if (lastPersistedByte < chunkStart || lastPersistedByte >= totalBytes) {
          throw const UploadClientException(
            'Réponse 308 invalide pendant l’upload miniature.',
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

  // The server treats a repeated finalize as success (see finalizeUpload in
  // functions/src/upload_session.ts). This catch is the safety net for the
  // rollout window, where an app build can still be talking to a backend that
  // predates that change: without it, a retry whose first attempt actually
  // succeeded surfaces as a failed upload for a video that is already live.
  static final RegExp _alreadyFinalizedPattern = RegExp(
    r'd[eé]j[aà]\s+finalis',
    caseSensitive: false,
  );

  bool _isAlreadyFinalizedError(Object error) {
    if (error is! FirebaseFunctionsException) {
      return false;
    }
    if (error.code != 'failed-precondition') {
      return false;
    }
    return _alreadyFinalizedPattern.hasMatch(error.message ?? '');
  }

  Future<bool> finalizeUpload({
    required String sessionId,
    required Map<String, dynamic> metadata,
  }) async {
    final callable = _functions.httpsCallable(
      'finalizeUpload',
      options: HttpsCallableOptions(timeout: _callableTimeout),
    );

    try {
      final data = await _callCallableWithRetry<Map<String, dynamic>>(
        callable,
        'finalizeUpload',
        {'sessionId': sessionId, 'metadata': metadata},
      );
      return (data['ok'] as bool?) ?? false;
    } catch (error) {
      if (_isAlreadyFinalizedError(error)) {
        return true;
      }
      rethrow;
    }
  }
}
