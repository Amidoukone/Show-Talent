import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:adfoot/config/app_environment.dart';
import 'package:adfoot/services/callable_auth_guard.dart';
import 'package:adfoot/services/client_logger.dart';

typedef VideoObservabilityLogEmitter = Future<void> Function(
  String source,
  String message, {
  Map<String, dynamic>? metadata,
});

typedef VideoActionLogEmitter = Future<void> Function(
  Map<String, dynamic> payload,
);

class VideoObservabilityService {
  VideoObservabilityService({
    ClientLogger? logger,
    FirebaseFunctions? functions,
    VideoObservabilityLogEmitter? logInfo,
    VideoObservabilityLogEmitter? logError,
    VideoActionLogEmitter? videoActionLog,
  })  : _logger = logger,
        _functions = functions,
        _logInfo = logInfo,
        _logError = logError,
        _videoActionLog = videoActionLog;

  static final VideoObservabilityService instance = VideoObservabilityService();

  final ClientLogger? _logger;
  final FirebaseFunctions? _functions;
  final VideoObservabilityLogEmitter? _logInfo;
  final VideoObservabilityLogEmitter? _logError;
  final VideoActionLogEmitter? _videoActionLog;

  FirebaseFunctions get _resolvedFunctions =>
      _functions ??
      FirebaseFunctions.instanceFor(
        region: AppEnvironmentConfig.functionsRegion,
      );

  Future<void> logPlaybackError({
    required String videoId,
    required String videoUrl,
    required String contextKey,
    required String reason,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    final details = _metadata({
      'event': 'play_error',
      'videoId': videoId,
      'videoUrl': videoUrl,
      'contextKey': contextKey,
      'reason': reason,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
      ...?metadata,
    });

    return _emitBoth(
      source: 'video_playback',
      clientMessage: 'play_error',
      action: 'play_error',
      status: 'failure',
      videoId: videoId,
      code: reason,
      message: error?.toString() ?? reason,
      metadata: details,
      asError: true,
    );
  }

  Future<void> logPlaybackRetry({
    required String videoId,
    required String videoUrl,
    required String contextKey,
    required String reason,
    bool purgeCachedFile = false,
    bool preferDownloadedFile = false,
    Map<String, dynamic>? metadata,
  }) {
    final details = _metadata({
      'event': 'retry',
      'videoId': videoId,
      'videoUrl': videoUrl,
      'contextKey': contextKey,
      'reason': reason,
      'purgeCachedFile': purgeCachedFile,
      'preferDownloadedFile': preferDownloadedFile,
      ...?metadata,
    });

    return _emitBoth(
      source: 'video_playback',
      clientMessage: 'retry',
      action: 'retry',
      status: 'retry',
      videoId: videoId,
      code: reason,
      message: reason,
      metadata: details,
      asError: false,
    );
  }

  Future<void> logActionFailure({
    required String action,
    String? videoId,
    String? code,
    String? message,
    Map<String, dynamic>? metadata,
  }) {
    final event = _failureEventName(action);
    final details = _metadata({
      'event': event,
      'action': action,
      'videoId': videoId,
      'code': code,
      'message': message,
      ...?metadata,
    });

    return _emitBoth(
      source: 'video_action',
      clientMessage: event,
      action: event,
      status: 'failure',
      videoId: videoId,
      code: code,
      message: message ?? event,
      metadata: details,
      asError: true,
    );
  }

  Future<void> logUploadFailure({
    required String stage,
    String? sessionId,
    String? code,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    final message = error?.toString() ?? code ?? stage;
    final details = _metadata({
      'event': 'upload_failed',
      'stage': stage,
      'sessionId': sessionId,
      'code': code,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
      ...?metadata,
    });

    return _emitBoth(
      source: 'video_upload',
      clientMessage: 'upload_failed',
      action: 'upload_failed',
      status: 'failure',
      videoId: sessionId,
      code: code ?? stage,
      message: message,
      metadata: details,
      asError: true,
    );
  }

  Future<void> logUploadInfo({
    required String event,
    required String stage,
    String? sessionId,
    Map<String, dynamic>? metadata,
  }) {
    final details = _metadata({
      'event': event,
      'stage': stage,
      'sessionId': sessionId,
      ...?metadata,
    });

    return _emitBoth(
      source: 'video_upload',
      clientMessage: event,
      action: event,
      status: 'info',
      videoId: sessionId,
      code: stage,
      message: event,
      metadata: details,
      asError: false,
    );
  }

  Future<void> _emitBoth({
    required String source,
    required String clientMessage,
    required String action,
    required String status,
    required String? videoId,
    required String? code,
    required String message,
    required Map<String, dynamic> metadata,
    required bool asError,
  }) async {
    if (asError) {
      await _emitError(source, clientMessage, metadata: metadata);
    } else {
      await _emitInfo(source, clientMessage, metadata: metadata);
    }

    await _emitVideoActionLog({
      'action': action,
      'videoId': videoId,
      'status': status,
      'code': code,
      'message': message,
      'extra': metadata,
      'platform': kIsWeb ? 'web' : 'mobile',
    });
  }

  Future<void> _emitVideoActionLog(Map<String, dynamic> payload) async {
    try {
      final emitter = _videoActionLog;
      if (emitter != null) {
        await emitter(payload);
        return;
      }

      final callable = _resolvedFunctions.httpsCallable(
        'videoActionLog',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 6)),
      );
      await CallableAuthGuard.call(callable, _metadata(payload));
    } catch (_) {}
  }

  Future<void> _emitInfo(
    String source,
    String message, {
    Map<String, dynamic>? metadata,
  }) {
    final emitter = _logInfo;
    if (emitter != null) {
      return emitter(source, message, metadata: metadata);
    }
    return (_logger ?? ClientLogger.instance).logInfo(
      source,
      message,
      metadata: metadata,
    );
  }

  Future<void> _emitError(
    String source,
    String message, {
    Map<String, dynamic>? metadata,
  }) {
    final emitter = _logError;
    if (emitter != null) {
      return emitter(source, message, metadata: metadata);
    }
    return (_logger ?? ClientLogger.instance).logError(
      source,
      message,
      metadata: metadata,
    );
  }

  String _failureEventName(String action) {
    switch (action) {
      case 'likeVideo':
        return 'like_failed';
      case 'shareVideo':
        return 'share_failed';
      case 'reportVideo':
        return 'report_failed';
      case 'deleteVideo':
        return 'delete_failed';
      default:
        final snake = action
            .replaceAllMapped(
              RegExp(r'([a-z0-9])([A-Z])'),
              (match) => '${match.group(1)}_${match.group(2)}',
            )
            .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
            .toLowerCase()
            .replaceAll(RegExp(r'_+'), '_')
            .replaceAll(RegExp(r'^_|_$'), '');
        return snake.endsWith('_failed') ? snake : '${snake}_failed';
    }
  }

  Map<String, dynamic> _metadata(Map<String, dynamic> raw) {
    return raw.map(
      (key, value) => MapEntry(key, _safeValue(value)),
    )..removeWhere((_, value) => value == null);
  }

  dynamic _safeValue(dynamic value) {
    if (value == null || value is bool || value is num || value is DateTime) {
      return value is DateTime ? value.toIso8601String() : value;
    }

    if (value is Duration) {
      return value.inMilliseconds;
    }

    if (value is String) {
      return value.length > 2000 ? value.substring(0, 2000) : value;
    }

    if (value is Iterable) {
      return value.take(20).map(_safeValue).toList(growable: false);
    }

    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries.take(40)) {
        result[entry.key.toString()] = _safeValue(entry.value);
      }
      result.removeWhere((_, entryValue) => entryValue == null);
      return result;
    }

    final asString = value.toString();
    return asString.length > 2000 ? asString.substring(0, 2000) : asString;
  }
}
