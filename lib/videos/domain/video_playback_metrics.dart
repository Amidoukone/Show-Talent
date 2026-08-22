import 'package:adfoot/services/app_logger.dart';

/// What one controller initialisation cost, and how it got there.
///
/// This is the record `VideoMetricsObserver` ships to `client_logs`, and it is
/// what told us — after the fact — that every playback session in production
/// was classified `high` and that 1080p was rebuffering at 55%. It travels
/// with the branch actually taken (`mp4_cache`, `mp4_stream`,
/// `mp4_stream_fallback`, `mp4_download`), because "the video was slow" is not
/// a diagnosis and the branch is.

enum VideoMetricType { initSuccess, initError }

class VideoMetricEvent {
  VideoMetricEvent({
    required this.type,
    required this.url,
    required this.isPreload,
    this.contextKey,
    this.duration,
    this.usedCache,
    this.error,
    this.initCount,
    this.cacheHits,
    this.errorCount,
    this.cacheHitRate,
    this.sourceType,
    this.sourceQuality,
    this.sourceHeight,
    this.sourceBitrate,
    this.cacheBypassed,
    this.playbackBranch,
    this.usedStreaming,
    this.usedStreamFallback,
    this.fallbackFromSourceType,
    this.recoveryReason,
    this.primaryInitDuration,
    this.fallbackDownloadDuration,
    this.fallbackInitDuration,
    this.fallbackCacheHit,
    this.reusedInFlightDownload,
  });

  final VideoMetricType type;
  final String url;
  final bool isPreload;
  final String? contextKey;
  final Duration? duration;
  final bool? usedCache;
  final Object? error;
  final int? initCount;
  final int? cacheHits;
  final int? errorCount;
  final double? cacheHitRate;
  final String? sourceType;
  final String? sourceQuality;
  final int? sourceHeight;
  final int? sourceBitrate;
  final bool? cacheBypassed;
  final String? playbackBranch;
  final bool? usedStreaming;
  final bool? usedStreamFallback;
  final String? fallbackFromSourceType;
  final String? recoveryReason;
  final Duration? primaryInitDuration;
  final Duration? fallbackDownloadDuration;
  final Duration? fallbackInitDuration;
  final bool? fallbackCacheHit;
  final bool? reusedInFlightDownload;

  VideoMetricEvent copyWith({
    int? initCount,
    int? cacheHits,
    int? errorCount,
    double? cacheHitRate,
  }) {
    return VideoMetricEvent(
      type: type,
      url: url,
      isPreload: isPreload,
      contextKey: contextKey,
      duration: duration,
      usedCache: usedCache,
      error: error,
      initCount: initCount ?? this.initCount,
      cacheHits: cacheHits ?? this.cacheHits,
      errorCount: errorCount ?? this.errorCount,
      cacheHitRate: cacheHitRate ?? this.cacheHitRate,
      sourceType: sourceType,
      sourceQuality: sourceQuality,
      sourceHeight: sourceHeight,
      sourceBitrate: sourceBitrate,
      cacheBypassed: cacheBypassed,
      playbackBranch: playbackBranch,
      usedStreaming: usedStreaming,
      usedStreamFallback: usedStreamFallback,
      fallbackFromSourceType: fallbackFromSourceType,
      recoveryReason: recoveryReason,
      primaryInitDuration: primaryInitDuration,
      fallbackDownloadDuration: fallbackDownloadDuration,
      fallbackInitDuration: fallbackInitDuration,
      fallbackCacheHit: fallbackCacheHit,
      reusedInFlightDownload: reusedInFlightDownload,
    );
  }
}

/// Counts initialisations, cache hits and errors, and hands each event on.
///
/// Lifted out of `VideoManager` with the event it produces: keeping a running
/// cache-hit rate is not part of opening a video, and mixing the two meant the
/// counters were reachable only through the class that owns every native
/// player in the app.
class VideoPlaybackMetricsRecorder {
  /// Where enriched events go. `VideoMetricsObserver` installs itself here.
  void Function(VideoMetricEvent event)? onMetrics;

  int _initCount = 0;
  int _cacheHits = 0;
  int _errorCount = 0;

  int get initCount => _initCount;
  int get cacheHits => _cacheHits;
  int get errorCount => _errorCount;

  double get cacheHitRate => _initCount == 0 ? 0.0 : _cacheHits / _initCount;

  String get _cacheRateLabel {
    if (_initCount == 0) return '0%';
    return '${(cacheHitRate * 100).toStringAsFixed(1)}%';
  }

  void record(VideoMetricEvent event) {
    switch (event.type) {
      case VideoMetricType.initSuccess:
        _initCount++;
        if (event.usedCache == true) _cacheHits++;
        AppLogger.debug(
          '[VideoMetrics] '
          '${event.isPreload ? 'preload' : 'active'} '
          'source=${event.sourceType} '
          'cache=${event.usedCache} '
          'cacheRate=$_cacheRateLabel '
          'errors=$_errorCount',
        );
      case VideoMetricType.initError:
        _errorCount++;
        AppLogger.debug(
          '[VideoMetrics] error source=${event.sourceType} '
          'url=${event.url} '
          'cacheRate=$_cacheRateLabel '
          'errors=$_errorCount',
        );
    }

    onMetrics?.call(
      event.copyWith(
        initCount: _initCount,
        cacheHits: _cacheHits,
        errorCount: _errorCount,
        cacheHitRate: cacheHitRate,
      ),
    );
  }
}
