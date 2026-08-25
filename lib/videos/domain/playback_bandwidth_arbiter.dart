import 'package:adfoot/models/video.dart';
import 'package:adfoot/services/app_logger.dart';

/// A `preloadSurrounding` call held back because the active video is still
/// streaming.
///
/// Released in two stages: the neighbour that earns a player as soon as the
/// visible video has rendered, the whole-file warms behind it only once that
/// stream reports itself healthy.
class DeferredPreloadRequest {
  DeferredPreloadRequest({
    required this.videos,
    required this.index,
    required this.preferForward,
    this.activeUrl,
  });

  final List<Video> videos;
  final int index;
  final bool preferForward;
  final String? activeUrl;

  /// Whether the neighbour that earns a player has already been started.
  ///
  /// The request is released in two stages — see
  /// [PlaybackBandwidthArbiter.takeDeferredPlayers] — and the second stage
  /// replays the whole thing, so without this the next player would be asked
  /// for twice.
  bool playersReleased = false;
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

  /// The resolved URL each context's visible video has rendered a frame for.
  ///
  /// The two events that decide whether the next player may open — the
  /// request to preload, and the first frame of the video on screen — race,
  /// and a video promoted from a preload renders *before* its own
  /// `preloadSurrounding` call is even made. Recording the answer instead of
  /// reacting to it makes the order irrelevant: whichever arrives second
  /// finds what the first left behind.
  final Map<String, String> _renderedUrlByContext = {};

  void markRendered(String contextKey, String resolvedUrl) {
    _renderedUrlByContext[contextKey] = resolvedUrl;
  }

  bool hasRendered(String contextKey, String? resolvedUrl) {
    if (resolvedUrl == null || resolvedUrl.isEmpty) return false;
    return _renderedUrlByContext[contextKey] == resolvedUrl;
  }

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

  /// Hands back the held request for its *player* stage only, once.
  ///
  /// A held request covers two different costs. Preparing the next player is
  /// one stream opening beside the visible one; the whole-file warms behind
  /// it are what starved a live stream in production. Releasing them together
  /// meant the next player waited for three smooth 700 ms ticks — a window a
  /// feed scrolled at any pace never reaches, so on a fast scroll nothing was
  /// ever prepared and every swipe paid a cold start.
  ///
  /// The request stays held: [takeDeferred] still owes the warms.
  DeferredPreloadRequest? takeDeferredPlayers(String contextKey) {
    final request = _deferredByContext[contextKey];
    if (request == null || request.playersReleased) return null;
    request.playersReleased = true;
    AppLogger.debug(
      '[PlaybackBandwidthArbiter] Next player released, warms still held -> '
      '${request.activeUrl}',
    );
    return request;
  }

  bool hasDeferred(String contextKey) =>
      _deferredByContext.containsKey(contextKey);

  /// Forgets everything held for a context that is going away.
  void forgetContext(String contextKey) {
    _streamingUrlsByContext.remove(contextKey);
    _deferredByContext.remove(contextKey);
    _renderedUrlByContext.remove(contextKey);
  }
}
