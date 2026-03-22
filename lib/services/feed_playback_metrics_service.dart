import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/video.dart';
import 'client_logger.dart';

typedef PlaybackMetricsEmitter = Future<void> Function(
  String source,
  String message, {
  Map<String, dynamic>? metadata,
});

class FeedPlaybackMetricsPolicy {
  const FeedPlaybackMetricsPolicy({
    this.sampleRate = 1.0,
  }) : assert(sampleRate >= 0 && sampleRate <= 1);

  final double sampleRate;

  factory FeedPlaybackMetricsPolicy.forCurrentBuild() {
    final defaultSampleRate = kReleaseMode ? 0.2 : 1.0;
    final configuredSampleRate = double.tryParse(
          const String.fromEnvironment('FEED_PLAYBACK_METRICS_SAMPLE_RATE'),
        ) ??
        defaultSampleRate;

    return FeedPlaybackMetricsPolicy(
      sampleRate: configuredSampleRate.clamp(0.0, 1.0).toDouble(),
    );
  }

  bool shouldLog(
    FeedPlaybackSessionSummary summary, {
    required double randomValue,
  }) {
    final shouldAlwaysLog = !summary.hadFirstFrame ||
        summary.rebufferCount > 0 ||
        summary.stallRecoveryCount > 0;
    if (shouldAlwaysLog) {
      return true;
    }
    if (sampleRate >= 1.0) {
      return true;
    }
    if (sampleRate <= 0.0) {
      return false;
    }
    return randomValue < sampleRate;
  }
}

class FeedPlaybackSessionSummary {
  const FeedPlaybackSessionSummary({
    required this.videoId,
    required this.entryContext,
    required this.sessionDuration,
    required this.watchDuration,
    required this.hadFirstFrame,
    required this.completed,
    required this.completionRate,
    required this.rebufferCount,
    required this.rebufferDuration,
    required this.rebufferRate,
    required this.stallRecoveryCount,
    required this.stallRecoverySuccessCount,
    required this.estimatedBytesPlayed,
    required this.endReason,
    this.playbackMode,
    this.contractPlaybackMode,
    this.networkTier,
    this.preferHlsRequested,
    this.timeToFirstFrame,
    this.stallRecoveryRate,
    this.initialResolvedUrl,
    this.finalResolvedUrl,
    this.initialSourceType,
    this.initialSourceQuality,
    this.initialSourceHeight,
    this.initialSourceBitrate,
    this.finalSourceType,
    this.finalSourceQuality,
    this.finalSourceHeight,
    this.finalSourceBitrate,
    this.sourceChangeCount = 0,
    this.maxPosition,
    this.reportedDuration,
    this.recoveryReasons = const <String, int>{},
  });

  final String videoId;
  final String entryContext;
  final String? playbackMode;
  final String? contractPlaybackMode;
  final String? networkTier;
  final bool? preferHlsRequested;
  final Duration sessionDuration;
  final Duration watchDuration;
  final Duration? timeToFirstFrame;
  final bool hadFirstFrame;
  final bool completed;
  final double completionRate;
  final int rebufferCount;
  final Duration rebufferDuration;
  final double rebufferRate;
  final int stallRecoveryCount;
  final int stallRecoverySuccessCount;
  final double? stallRecoveryRate;
  final int estimatedBytesPlayed;
  final String endReason;
  final String? initialResolvedUrl;
  final String? finalResolvedUrl;
  final String? initialSourceType;
  final String? initialSourceQuality;
  final int? initialSourceHeight;
  final int? initialSourceBitrate;
  final String? finalSourceType;
  final String? finalSourceQuality;
  final int? finalSourceHeight;
  final int? finalSourceBitrate;
  final int sourceChangeCount;
  final Duration? maxPosition;
  final Duration? reportedDuration;
  final Map<String, int> recoveryReasons;

  Map<String, dynamic> toMetadata() {
    return {
      'videoId': videoId,
      'entryContext': entryContext,
      'playbackMode': playbackMode,
      'contractPlaybackMode': contractPlaybackMode,
      'networkTier': networkTier,
      'preferHlsRequested': preferHlsRequested,
      'sessionDurationMs': sessionDuration.inMilliseconds,
      'watchDurationMs': watchDuration.inMilliseconds,
      'timeToFirstFrameMs': timeToFirstFrame?.inMilliseconds,
      'hadFirstFrame': hadFirstFrame,
      'completed': completed,
      'completionRate': completionRate,
      'completionThreshold': FeedPlaybackSessionTracker.completionThreshold,
      'rebufferCount': rebufferCount,
      'rebufferDurationMs': rebufferDuration.inMilliseconds,
      'rebufferRate': rebufferRate,
      'stallRecoveryCount': stallRecoveryCount,
      'stallRecoverySuccessCount': stallRecoverySuccessCount,
      'stallRecoveryRate': stallRecoveryRate,
      'estimatedBytesPlayed': estimatedBytesPlayed,
      'estimatedBytesPlayedApprox': true,
      'endReason': endReason,
      'initialResolvedUrl': initialResolvedUrl,
      'finalResolvedUrl': finalResolvedUrl,
      'initialSourceType': initialSourceType,
      'initialSourceQuality': initialSourceQuality,
      'initialSourceHeight': initialSourceHeight,
      'initialSourceBitrate': initialSourceBitrate,
      'finalSourceType': finalSourceType,
      'finalSourceQuality': finalSourceQuality,
      'finalSourceHeight': finalSourceHeight,
      'finalSourceBitrate': finalSourceBitrate,
      'sourceChangeCount': sourceChangeCount,
      'maxPositionMs': maxPosition?.inMilliseconds,
      'reportedDurationMs': reportedDuration?.inMilliseconds,
      'recoveryReasons': recoveryReasons,
    };
  }
}

class FeedPlaybackSessionTracker {
  FeedPlaybackSessionTracker({
    required this.videoId,
    required this.entryContext,
    required DateTime Function() now,
    this.playbackMode,
    this.hasMultipleMp4Sources = false,
    this.networkTier,
    this.preferHlsRequested,
    String? resolvedUrl,
    VideoSource? source,
  })  : _now = now,
        _startedAt = now() {
    updateSource(resolvedUrl: resolvedUrl, source: source);
  }

  static const double completionThreshold = 0.9;

  final String videoId;
  final String entryContext;
  final String? playbackMode;
  final bool hasMultipleMp4Sources;
  final String? networkTier;
  final bool? preferHlsRequested;
  final DateTime Function() _now;
  final DateTime _startedAt;

  DateTime? _firstFrameAt;
  Duration _watchDuration = Duration.zero;
  Duration _lastPosition = Duration.zero;
  Duration _maxPosition = Duration.zero;
  Duration _reportedDuration = Duration.zero;
  bool _completed = false;

  bool _lastBuffering = false;
  DateTime? _bufferingStartedAt;
  int _rebufferCount = 0;
  Duration _rebufferDuration = Duration.zero;

  int _recoveryAttempts = 0;
  int _recoverySuccessCount = 0;
  int _pendingRecoveryAttempts = 0;
  final Map<String, int> _recoveryReasons = <String, int>{};

  String? _initialResolvedUrl;
  String? _finalResolvedUrl;
  String? _initialSourceType;
  String? _initialSourceQuality;
  int? _initialSourceHeight;
  int? _initialSourceBitrate;
  String? _finalSourceType;
  String? _finalSourceQuality;
  int? _finalSourceHeight;
  int? _finalSourceBitrate;
  int _sourceChangeCount = 0;

  int? _currentSourceBitrate;
  String? _currentSourceUrl;
  bool _finished = false;
  double _estimatedBytesPlayed = 0;

  void updateSource({
    String? resolvedUrl,
    VideoSource? source,
  }) {
    if (_finished) {
      return;
    }

    final effectiveResolvedUrl = resolvedUrl?.trim();
    final nextSourceUrl = effectiveResolvedUrl?.isNotEmpty == true
        ? effectiveResolvedUrl
        : source?.url;
    final nextSourceType = _inferSourceType(nextSourceUrl, source);
    final nextSourceQuality = source?.quality;
    final nextSourceHeight = source?.height;
    final nextSourceBitrate = source?.bitrate;

    if (_initialResolvedUrl == null &&
        effectiveResolvedUrl?.isNotEmpty == true) {
      _initialResolvedUrl = effectiveResolvedUrl;
    }
    _finalResolvedUrl = effectiveResolvedUrl ?? _finalResolvedUrl;

    if (_initialSourceType == null && nextSourceType != null) {
      _initialSourceType = nextSourceType;
      _initialSourceQuality = nextSourceQuality;
      _initialSourceHeight = nextSourceHeight;
      _initialSourceBitrate = nextSourceBitrate;
    }

    final sourceChanged = (_currentSourceUrl != null &&
            nextSourceUrl != null &&
            nextSourceUrl.isNotEmpty &&
            _currentSourceUrl != nextSourceUrl) ||
        (_currentSourceUrl == null &&
            nextSourceUrl != null &&
            nextSourceUrl.isNotEmpty &&
            _initialSourceType != null);

    if (sourceChanged) {
      _sourceChangeCount += 1;
    }

    if (nextSourceUrl != null && nextSourceUrl.isNotEmpty) {
      _currentSourceUrl = nextSourceUrl;
    }
    _currentSourceBitrate = nextSourceBitrate ?? _currentSourceBitrate;
    _finalSourceType = nextSourceType ?? _finalSourceType;
    _finalSourceQuality = nextSourceQuality ?? _finalSourceQuality;
    _finalSourceHeight = nextSourceHeight ?? _finalSourceHeight;
    _finalSourceBitrate = nextSourceBitrate ?? _finalSourceBitrate;
  }

  void markFirstFrameRendered() {
    if (_finished) {
      return;
    }
    _firstFrameAt ??= _now();
    if (_pendingRecoveryAttempts > 0) {
      _recoverySuccessCount += _pendingRecoveryAttempts;
      _pendingRecoveryAttempts = 0;
    }
  }

  void recordRecoveryAttempt(String reason) {
    if (_finished) {
      return;
    }
    _recoveryAttempts += 1;
    _pendingRecoveryAttempts += 1;
    _recoveryReasons.update(reason, (value) => value + 1, ifAbsent: () => 1);
  }

  void recordPlaybackSample({
    required Duration position,
    required Duration? duration,
    required bool isBuffering,
  }) {
    if (_finished) {
      return;
    }

    final now = _now();
    final safePosition = position < Duration.zero ? Duration.zero : position;
    final safeDuration =
        duration == null || duration <= Duration.zero ? null : duration;

    if (safeDuration != null && safeDuration > _reportedDuration) {
      _reportedDuration = safeDuration;
    }
    if (safePosition > _maxPosition) {
      _maxPosition = safePosition;
    }

    if (isBuffering != _lastBuffering) {
      if (isBuffering && _firstFrameAt != null) {
        _rebufferCount += 1;
        _bufferingStartedAt = now;
      } else if (!isBuffering && _bufferingStartedAt != null) {
        _rebufferDuration += now.difference(_bufferingStartedAt!);
        _bufferingStartedAt = null;
      }
      _lastBuffering = isBuffering;
    }

    if (!isBuffering) {
      final delta = _positionDelta(
        previous: _lastPosition,
        current: safePosition,
        duration: safeDuration ?? _reportedDuration,
      );
      if (delta > Duration.zero) {
        _watchDuration += delta;
        final bitrate = _currentSourceBitrate;
        if (bitrate != null && bitrate > 0) {
          _estimatedBytesPlayed +=
              (delta.inMilliseconds / 1000.0) * bitrate / 8.0;
        }
      }
    }

    _lastPosition = safePosition;
    if (!_completed && _reachesCompletion(safePosition, safeDuration)) {
      _completed = true;
    }
  }

  FeedPlaybackSessionSummary finish({required String endReason}) {
    if (_finished) {
      throw StateError('Playback session already finished.');
    }
    _finished = true;

    final finishedAt = _now();
    if (_bufferingStartedAt != null) {
      _rebufferDuration += finishedAt.difference(_bufferingStartedAt!);
      _bufferingStartedAt = null;
    }

    final sessionDuration = finishedAt.difference(_startedAt);
    final watchDurationMs = _watchDuration.inMilliseconds;
    final rebufferRate = watchDurationMs > 0
        ? _rebufferDuration.inMilliseconds / watchDurationMs
        : (_rebufferCount > 0 ? 1.0 : 0.0);
    final stallRecoveryRate = _recoveryAttempts > 0
        ? _recoverySuccessCount / _recoveryAttempts
        : null;

    return FeedPlaybackSessionSummary(
      videoId: videoId,
      entryContext: entryContext,
      playbackMode: _resolvePlaybackMode(),
      contractPlaybackMode: playbackMode,
      networkTier: networkTier,
      preferHlsRequested: preferHlsRequested,
      sessionDuration: sessionDuration,
      watchDuration: _watchDuration,
      timeToFirstFrame: _firstFrameAt?.difference(_startedAt),
      hadFirstFrame: _firstFrameAt != null,
      completed: _completed,
      completionRate: _completed ? 1.0 : 0.0,
      rebufferCount: _rebufferCount,
      rebufferDuration: _rebufferDuration,
      rebufferRate: rebufferRate,
      stallRecoveryCount: _recoveryAttempts,
      stallRecoverySuccessCount: _recoverySuccessCount,
      stallRecoveryRate: stallRecoveryRate,
      estimatedBytesPlayed: _estimatedBytesPlayed.round(),
      endReason: endReason,
      initialResolvedUrl: _initialResolvedUrl,
      finalResolvedUrl: _finalResolvedUrl,
      initialSourceType: _initialSourceType,
      initialSourceQuality: _initialSourceQuality,
      initialSourceHeight: _initialSourceHeight,
      initialSourceBitrate: _initialSourceBitrate,
      finalSourceType: _finalSourceType,
      finalSourceQuality: _finalSourceQuality,
      finalSourceHeight: _finalSourceHeight,
      finalSourceBitrate: _finalSourceBitrate,
      sourceChangeCount: _sourceChangeCount,
      maxPosition: _maxPosition > Duration.zero ? _maxPosition : null,
      reportedDuration:
          _reportedDuration > Duration.zero ? _reportedDuration : null,
      recoveryReasons: Map<String, int>.unmodifiable(_recoveryReasons),
    );
  }

  String? _resolvePlaybackMode() {
    final sourceType = _finalSourceType ?? _initialSourceType;
    if (sourceType == 'mp4') {
      return hasMultipleMp4Sources ? 'multi_rendition_mp4' : 'mp4_only';
    }
    if (sourceType == 'hls') {
      return playbackMode ?? 'single_rendition_hls';
    }
    if (hasMultipleMp4Sources) {
      return 'multi_rendition_mp4';
    }
    return playbackMode;
  }

  Duration _positionDelta({
    required Duration previous,
    required Duration current,
    required Duration duration,
  }) {
    if (current >= previous) {
      return current - previous;
    }

    if (duration <= Duration.zero) {
      return Duration.zero;
    }

    final thresholdMs = duration.inMilliseconds * completionThreshold;
    final likelyLooped = previous.inMilliseconds >= thresholdMs &&
        current.inMilliseconds <= duration.inMilliseconds * 0.2;
    if (!likelyLooped) {
      return Duration.zero;
    }

    return (duration - previous) + current;
  }

  bool _reachesCompletion(Duration position, Duration? duration) {
    final effectiveDuration = duration ?? _reportedDuration;
    if (effectiveDuration <= Duration.zero) {
      return false;
    }
    return position.inMilliseconds >=
            effectiveDuration.inMilliseconds * completionThreshold ||
        _maxPosition.inMilliseconds >=
            effectiveDuration.inMilliseconds * completionThreshold;
  }

  String? _inferSourceType(String? url, VideoSource? source) {
    final declared = source?.type?.trim().toLowerCase();
    if (declared != null && declared.isNotEmpty) {
      return declared;
    }
    final value = (url ?? source?.url ?? '').toLowerCase();
    if (value.contains('.m3u8')) {
      return 'hls';
    }
    if (value.contains('.mp4')) {
      return 'mp4';
    }
    return null;
  }
}

class FeedPlaybackMetricsLogger {
  FeedPlaybackMetricsLogger({
    ClientLogger? logger,
    FeedPlaybackMetricsPolicy? policy,
    double Function()? random,
    PlaybackMetricsEmitter? emitInfo,
  })  : _logger = logger,
        _policy = policy ?? FeedPlaybackMetricsPolicy.forCurrentBuild(),
        _random = random ?? Random().nextDouble,
        _emitInfo = emitInfo;

  final ClientLogger? _logger;
  final FeedPlaybackMetricsPolicy _policy;
  final double Function() _random;
  final PlaybackMetricsEmitter? _emitInfo;

  Future<void> logSession(FeedPlaybackSessionSummary summary) async {
    if (!_policy.shouldLog(summary, randomValue: _random())) {
      return;
    }

    await (_emitInfo ??
            ((
              String source,
              String message, {
              Map<String, dynamic>? metadata,
            }) {
              return (_logger ?? ClientLogger.instance).logInfo(
                source,
                message,
                metadata: metadata,
              );
            }))
        .call(
      'feed_playback',
      'Feed playback session',
      metadata: summary.toMetadata(),
    );
  }
}
