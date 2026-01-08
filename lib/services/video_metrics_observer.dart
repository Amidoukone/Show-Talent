import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/client_logger.dart';
import '../widgets/video_manager.dart';

class VideoMetricsObserver {
  VideoMetricsObserver({
    ClientLogger? logger,
    VideoManager? videoManager,
  })  : _logger = logger ?? ClientLogger.instance,
        _videoManager = videoManager;

  final ClientLogger _logger;
  final VideoManager? _videoManager;

  void handle(VideoMetricEvent event) {
    final metadata = <String, dynamic>{
      'url': event.url,
      'isPreload': event.isPreload,
      'durationMs': event.duration?.inMilliseconds,
      'usedCache': event.usedCache,
      'cacheHitRate': event.cacheHitRate,
      'initCount': event.initCount,
      'cacheHits': event.cacheHits,
      'errorCount': event.errorCount,
      'networkTier': _videoManager?.currentProfile?.tier.name,
      'preferHls': _videoManager?.currentProfile?.preferHls,
      'adaptiveEnabled': _videoManager?.adaptiveSourcesEnabled,
      'platform': kIsWeb ? 'web' : 'native',
    };

    if (event.type == VideoMetricType.initError) {
      metadata['error'] = event.error.toString();
      unawaited(
        _logger.logError(
          'video_manager',
          'Video init error',
          metadata: metadata,
        ),
      );
      return;
    }

    unawaited(
      _logger.logInfo(
        'video_manager',
        'Video init success',
        metadata: metadata,
      ),
    );
  }
}
