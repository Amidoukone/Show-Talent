import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../services/client_logger.dart';
import '../widgets/video_manager.dart';

typedef ClientLogEmitter = Future<void> Function(
  String source,
  String message, {
  Map<String, dynamic>? metadata,
});

class VideoMetricsPolicy {
  const VideoMetricsPolicy({
    this.captureErrors = true,
    this.successSampleRate = 1.0,
    this.includePreloadSuccess = true,
  }) : assert(successSampleRate >= 0 && successSampleRate <= 1);

  final bool captureErrors;
  final double successSampleRate;
  final bool includePreloadSuccess;

  bool get captureSuccess => successSampleRate > 0;

  factory VideoMetricsPolicy.forCurrentBuild() {
    final defaultSampleRate = kReleaseMode ? 0.0 : 1.0;
    final configuredSampleRate = double.tryParse(
          const String.fromEnvironment('VIDEO_METRICS_SUCCESS_SAMPLE_RATE'),
        ) ??
        defaultSampleRate;
    final sampleRate = configuredSampleRate.clamp(0.0, 1.0).toDouble();

    return VideoMetricsPolicy(
      captureErrors: true,
      successSampleRate: sampleRate,
      includePreloadSuccess: bool.fromEnvironment(
        'VIDEO_METRICS_INCLUDE_PRELOAD_SUCCESS',
        defaultValue: !kReleaseMode,
      ),
    );
  }
}

class VideoMetricsObserver {
  VideoMetricsObserver({
    ClientLogger? logger,
    VideoManager? videoManager,
    VideoMetricsPolicy? policy,
    double Function()? random,
    ClientLogEmitter? logInfo,
    ClientLogEmitter? logError,
  })  : _logger = logger,
        _videoManager = videoManager,
        _policy = policy ?? VideoMetricsPolicy.forCurrentBuild(),
        _random = random ?? Random().nextDouble,
        _logInfo = logInfo,
        _logError = logError;

  final ClientLogger? _logger;
  final VideoManager? _videoManager;
  final VideoMetricsPolicy _policy;
  final double Function() _random;
  final ClientLogEmitter? _logInfo;
  final ClientLogEmitter? _logError;

  void handle(VideoMetricEvent event) {
    if (!_shouldLog(event)) {
      return;
    }

    final metadata = <String, dynamic>{
      'url': event.url,
      'isPreload': event.isPreload,
      'entryContext': event.contextKey,
      'durationMs': event.duration?.inMilliseconds,
      'usedCache': event.usedCache,
      'cacheHitRate': event.cacheHitRate,
      'initCount': event.initCount,
      'cacheHits': event.cacheHits,
      'errorCount': event.errorCount,
      'sourceType': event.sourceType,
      'sourceQuality': event.sourceQuality,
      'sourceHeight': event.sourceHeight,
      'sourceBitrate': event.sourceBitrate,
      'requestedHls': event.requestedHls,
      'cacheBypassed': event.cacheBypassed,
      'playbackBranch': event.playbackBranch,
      'hlsSuppressedReason': event.hlsSuppressedReason,
      'manifestHost': event.manifestHost,
      'manifestPath': event.manifestPath,
      'manifestHasToken': event.manifestHasToken,
      'usedStreaming': event.usedStreaming,
      'usedStreamFallback': event.usedStreamFallback,
      'fallbackFromSourceType': event.fallbackFromSourceType,
      'recoveryReason': event.recoveryReason,
      'primaryInitDurationMs': event.primaryInitDuration?.inMilliseconds,
      'fallbackDownloadDurationMs':
          event.fallbackDownloadDuration?.inMilliseconds,
      'fallbackInitDurationMs': event.fallbackInitDuration?.inMilliseconds,
      'fallbackCacheHit': event.fallbackCacheHit,
      'reusedInFlightDownload': event.reusedInFlightDownload,
      'networkTier': _videoManager?.currentProfile?.tier.name,
      'preferHls': _videoManager?.currentProfile?.preferHls,
      'adaptiveEnabled': _videoManager?.adaptiveSourcesEnabled,
      'hlsStrategyEnabled': _videoManager?.hlsStrategyEnabled,
      'platform': kIsWeb ? 'web' : 'native',
    };

    if (event.type == VideoMetricType.initError) {
      metadata['error'] = event.error.toString();
      unawaited(
        _emitError(
          'video_manager',
          'Video init error',
          metadata: metadata,
        ),
      );
      return;
    }

    unawaited(
      _emitInfo(
        'video_manager',
        'Video init success',
        metadata: metadata,
      ),
    );
  }

  bool _shouldLog(VideoMetricEvent event) {
    if (event.type == VideoMetricType.initError) {
      return _policy.captureErrors;
    }

    if (!_policy.captureSuccess) {
      return false;
    }

    if (event.isPreload && !_policy.includePreloadSuccess) {
      return false;
    }

    if (_policy.successSampleRate >= 1.0) {
      return true;
    }

    return _random() < _policy.successSampleRate;
  }

  Future<void> _emitInfo(
    String source,
    String message, {
    Map<String, dynamic>? metadata,
  }) {
    final logger = _logInfo;
    if (logger != null) {
      return logger(source, message, metadata: metadata);
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
    final logger = _logError;
    if (logger != null) {
      return logger(source, message, metadata: metadata);
    }
    return (_logger ?? ClientLogger.instance).logError(
      source,
      message,
      metadata: metadata,
    );
  }
}
