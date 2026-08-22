import 'package:adfoot/models/video.dart';
import 'package:adfoot/services/app_logger.dart';

/// A `preloadSurrounding` call held back because the active video is still
/// streaming, replayed verbatim once that stream is healthy.
class DeferredPreloadRequest {
  const DeferredPreloadRequest({
    required this.videos,
    required this.index,
    required this.preferForward,
    this.activeUrl,
  });

  final List<Video> videos;
  final int index;
  final bool preferForward;
  final String? activeUrl;
}

/// Decides who gets the connection: the video on screen, or its neighbours.
///
/// Reported from production: a freshly published video — the only one in no
/// cache at all — paused and resumed continuously for its whole duration, on
/// the tile and again after scrolling away and back, while every already
/// cached video played normally. No recovery ran and nothing was logged,
/// because nothing failed: the player was simply starved by concurrent
/// downloads of the file it was trying to stream.
///
/// A preload is a *full file download*. Firing two or three of them next to a
/// live stream means the clip on screen competes with its own neighbours for
/// the same connection. So while a video is streaming, its context's preloads
/// are held; they are replayed the moment the stream reports itself healthy
/// (`SmartVideoPlayer`'s stall watchdog) or the active video turns out to be
/// playing from cache.
///
/// Lifted out of `VideoManager` intact: this is a decision with a production
/// incident behind it, not a piece of plumbing, and it deserves to be
/// findable.
class PlaybackBandwidthArbiter {
  /// Resolved URLs currently being played straight off the network, per
  /// context.
  final Map<String, Set<String>> _streamingUrlsByContext = {};

  /// The preload request each context owes, once its stream is healthy.
  final Map<String, DeferredPreloadRequest> _deferredByContext = {};

  void markStreaming(
    String contextKey,
    String resolvedUrl, {
    required bool isStreaming,
  }) {
    if (isStreaming) {
      _streamingUrlsByContext
          .putIfAbsent(contextKey, () => <String>{})
          .add(resolvedUrl);
      return;
    }

    final streaming = _streamingUrlsByContext[contextKey];
    if (streaming == null) return;
    streaming.remove(resolvedUrl);
    if (streaming.isEmpty) {
      _streamingUrlsByContext.remove(contextKey);
    }
  }

  bool isStreamingUrl(String contextKey, String? resolvedUrl) {
    if (resolvedUrl == null || resolvedUrl.isEmpty) return false;
    return _streamingUrlsByContext[contextKey]?.contains(resolvedUrl) ?? false;
  }

  /// Holds [request] until this context's stream is healthy.
  void defer(String contextKey, DeferredPreloadRequest request) {
    _deferredByContext[contextKey] = request;
    AppLogger.debug(
      '[PlaybackBandwidthArbiter] Preload deferred: active video still '
      'streaming -> ${request.activeUrl}',
    );
  }

  /// Drops any held request for [contextKey] without replaying it.
  void clearDeferred(String contextKey) {
    _deferredByContext.remove(contextKey);
  }

  /// Hands back the request this context owes, if any.
  DeferredPreloadRequest? takeDeferred(String contextKey) =>
      _deferredByContext.remove(contextKey);

  bool hasDeferred(String contextKey) =>
      _deferredByContext.containsKey(contextKey);

  /// Forgets everything held for a context that is going away.
  void forgetContext(String contextKey) {
    _streamingUrlsByContext.remove(contextKey);
    _deferredByContext.remove(contextKey);
  }
}
