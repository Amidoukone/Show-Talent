import 'dart:async';

import 'package:adfoot/models/video.dart';
import 'package:adfoot/videos/video_manager.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';

class VideoFocusOrchestrator {
  VideoFocusOrchestrator({
    required this.contextKey,
    required this.videoManager,
    required List<Video> videos,
    this.onRequestMore,
    this.disposeWindow = 25,
    this.settleDelay = const Duration(milliseconds: 120),
    this.now = DateTime.now,
    this.preserveActiveOnDispose = false,
  }) : _videos = List.of(videos);

  final String contextKey;
  final VideoManager videoManager;
  final Future<void> Function()? onRequestMore;
  final int disposeWindow;

  /// Whether [onDispose] keeps the on-screen player alive (see its doc
  /// comment) instead of releasing every player this context holds.
  ///
  /// Opt-in, not the default: it is correct for the home feed, where exactly
  /// one context exists for the app's whole life and `_globalMaxActive` is
  /// the only ceiling that matters. It is the wrong default for a
  /// per-profile video view (`ProfileVideoScrollView`) -- a fresh contextKey
  /// per profile visited -- because `releaseControllersExcept` does not
  /// forget the context's preload/bandwidth/UI bookkeeping the way
  /// `disposeAllForContext` does, and a session that opens several players'
  /// video views would accumulate one stale bookkeeping set per profile
  /// until something else eventually tears the context down. A context used
  /// once and rarely revisited has nothing to gain from the optimization
  /// and should keep the full, immediate cleanup.
  final bool preserveActiveOnDispose;

  /// How long a focus request that lands on the heels of another one waits to
  /// see whether the user is still moving.
  ///
  /// A vertical `PageView` reports every page a fling crosses, not just the
  /// one it lands on, and each report opened a controller: six pages flicked
  /// past meant six network streams and six native players started for videos
  /// nobody would watch — all of them competing for bandwidth and for the
  /// device's decoder instances with the one video that was about to be on
  /// screen. The request token already discarded their *results*; nothing
  /// stopped them being started.
  ///
  /// 120 ms is shorter than any deliberate swipe and longer than the gap
  /// between the page reports of a single fling, so a normal scroll is
  /// untouched and a fling collapses to the page it settles on.
  final Duration settleDelay;

  /// Injectable clock, so the settle window can be exercised in tests without
  /// making them wait on wall time.
  final DateTime Function() now;

  List<Video> _videos;
  bool _isDisposed = false;
  int _requestToken = 0;
  int? _lastFocusedIndex;
  DateTime? _lastRequestAt;

  /// The URL [onDispose] keeps alive, when [preserveActiveOnDispose].
  ///
  /// A URL, not `_videos[_lastFocusedIndex]` read at dispose time: the list
  /// can be replaced by [updateVideos] (a refresh, a reorder) after the last
  /// successful focus, which would silently repoint that index at a
  /// different video. Set only once a controller for it is confirmed live
  /// (see the end of [onIndexChanged]), never merely attempted -- a focus
  /// that failed to initialize (a dropped connection mid-swipe) must not
  /// make `onDispose` think a controller exists for it; `onDispose` would
  /// then keep nothing and tear down the controller that is actually
  /// cached and on screen.
  String? _lastFocusedUrl;

  void updateVideos(List<Video> videos) {
    _videos = List.of(videos);
  }

  Future<CachedVideoPlayerPlus?> onIndexChanged(int index) async {
    if (_isDisposed) return null;
    if (index < 0 || index >= _videos.length) return null;

    final localToken = ++_requestToken;

    // Only a request arriving on the heels of another one waits. A deliberate
    // swipe, and the first activation of a freshly opened feed, pay nothing.
    final previousRequestAt = _lastRequestAt;
    final requestedAt = now();
    _lastRequestAt = requestedAt;
    if (shouldWaitForScrollToSettle(
      previousRequestAt: previousRequestAt,
      requestedAt: requestedAt,
    )) {
      await Future<void>.delayed(settleDelay);
      if (_isStale(localToken)) return null;
      // The feed can shrink under us while we wait (a delete, a refresh).
      if (index >= _videos.length) return null;
    }

    final currentVideo = _videos[index];
    final currentUrl = currentVideo.videoUrl;
    final preferForwardPreload =
        _lastFocusedIndex == null ? true : index >= _lastFocusedIndex!;
    _lastFocusedIndex = index;

    await videoManager.pauseAllExcept(contextKey, currentUrl);
    if (_isStale(localToken)) return null;

    final resolvedUrl = videoManager.getResolvedUrl(contextKey, currentUrl);
    final canReuseExisting = videoManager.shouldReuseControllerForRequest(
      originalUrl: currentUrl,
      resolvedUrl: resolvedUrl,
      sources: currentVideo.sources,
      isPreload: false,
    );

    var player = canReuseExisting
        ? videoManager.getController(contextKey, currentUrl)
        : null;
    final ctrl = player?.controller;
    bool ctrlReady = false;
    try {
      ctrlReady =
          ctrl != null && ctrl.value.isInitialized && !ctrl.value.hasError;
    } catch (_) {
      ctrlReady = false;
    }

    if (!ctrlReady) {
      try {
        player = await videoManager.initializeController(
          contextKey,
          currentUrl,
          sources: currentVideo.sources,
          autoPlay: true,
          activeUrl: currentUrl,
        );
      } catch (_) {
        return null;
      }
    }

    if (_isStale(localToken)) return player;

    // The manager may have released this controller while we were awaiting
    // it, and a disposed `CachedVideoPlayerPlus` still reports
    // `isInitialized == true` with no error — which is exactly why
    // `VideoManager.attempt()` re-checks before handing one back from its
    // LRU. Nothing re-checked here.
    //
    // `_purgeAndReloadController` reaches `disposeUrls` for this very URL on
    // an adaptive rendition change, on automatic recovery and on a manual
    // retry, all of which can land while this await is suspended. Playing the
    // result then calls into a native player id that no longer exists, from a
    // future nobody is watching. If the manager no longer holds it, it is not
    // ours to start.
    final live = videoManager.getController(contextKey, currentUrl);
    if (live == null || !identical(live, player)) return null;

    // Only here, not at the top of the method: this is the first point a
    // controller for [currentUrl] is confirmed to actually exist in the
    // manager's LRU, not merely attempted. See the doc comment on
    // [_lastFocusedUrl].
    _lastFocusedUrl = currentUrl;

    final actualCtrl = player?.controller;
    bool shouldPlay = false;
    try {
      shouldPlay = actualCtrl != null &&
          actualCtrl.value.isInitialized &&
          !actualCtrl.value.hasError &&
          !actualCtrl.value.isPlaying &&
          // The request token above answers "did the user scroll on?", and it
          // is the wrong question for the case the user reported: leaving the
          // *app* while a video is loading does not change the focused index,
          // so nothing here was stale and this played to a screen nobody was
          // looking at. The manager owns the answer to "may anything start
          // right now", because it is also the one that starts playback
          // itself inside `initializeController(autoPlay: true)`.
          videoManager.canStartPlayback(contextKey, currentUrl);
    } catch (_) {
      shouldPlay = false;
    }
    if (shouldPlay) {
      try {
        await actualCtrl!.play();
      } catch (_) {}
    }

    if (!_isStale(localToken)) {
      // Keep the visible item on the critical path. Preload only after the
      // active controller is attached so background work cannot delay startup.
      unawaited(
        videoManager.preloadSurrounding(
          contextKey,
          _videos,
          index,
          activeUrl: currentUrl,
          preferForward: preferForwardPreload,
        ),
      );
    }

    if (!_isStale(localToken)) {
      await _disposeFarPlayers(index, localToken);
    }

    if (!_isDisposed && onRequestMore != null && index >= _videos.length - 2) {
      await onRequestMore!();
    }

    return player;
  }

  /// Tears down this orchestrator's focus requests.
  ///
  /// `MainScreen` swaps its body between destinations instead of keeping
  /// them in an `IndexedStack`, so leaving a tab disposes this and a return
  /// builds a fresh one. The default, [preserveActiveOnDispose] false,
  /// disposes every native player this context was holding, same as always.
  ///
  /// [preserveActiveOnDispose] true gives back every player except the one
  /// on screen instead. Disposing *every* controller, including the one the
  /// user was actually watching, used to mean a return always paid a cold
  /// start even though the video was already loaded -- measured on
  /// adfoot-production (`docs/audit-lecture-video-2026-10-17.md`): 105
  /// sessions, average 1.4s to first frame, home feed sessions far worse than
  /// a warm profile-tab cache (112ms). Mirrors
  /// `VideoFeedPager._releaseNeighboursForBackground`, the same treatment
  /// already proven in production for backgrounding the whole app: keep the
  /// visible player, release the rest. `VideoManager._globalMaxActive`
  /// remains the safety net against the MediaCodec exhaustion full teardown
  /// here originally guarded against (two incidents, August 2026) -- a kept
  /// Home player competing with, say, Profil's static thumbnails (no live
  /// players there, confirmed September 2026) does not approach that ceiling.
  Future<void> onDispose() async {
    _isDisposed = true;
    _requestToken++;
    await videoManager.pauseAll(contextKey);

    if (!preserveActiveOnDispose) {
      await videoManager.disposeAllForContext(contextKey);
      return;
    }

    await videoManager.releaseControllersExcept(contextKey, _lastFocusedUrl);
  }

  /// Whether this focus request should hold back and see where the scroll
  /// lands.
  ///
  /// Only a request that arrives inside [settleDelay] of the previous one
  /// waits, which is what separates a fling — many page reports in quick
  /// succession — from a deliberate swipe. The first request of a freshly
  /// opened feed has no predecessor and never waits, so cold start is
  /// untouched.
  bool shouldWaitForScrollToSettle({
    required DateTime? previousRequestAt,
    required DateTime requestedAt,
  }) {
    if (settleDelay <= Duration.zero || previousRequestAt == null) {
      return false;
    }
    return requestedAt.difference(previousRequestAt) < settleDelay;
  }

  bool _isStale(int token) => _isDisposed || token != _requestToken;

  Future<void> _disposeFarPlayers(int index, int token) async {
    if (_videos.length <= disposeWindow || _isStale(token)) return;

    final start = (index - disposeWindow ~/ 2).clamp(0, _videos.length).toInt();
    final end = (start + disposeWindow).clamp(0, _videos.length).toInt();

    final keepUrls = _videos.sublist(start, end).map((v) => v.videoUrl).toSet();
    final activeUrls = videoManager.activeOriginalUrlsForContext(contextKey);
    if (activeUrls.isEmpty) return;

    final toDispose = activeUrls
        .where((url) => !keepUrls.contains(url))
        .toList(growable: false);

    if (toDispose.isEmpty || _isStale(token)) return;

    await videoManager.disposeUrls(contextKey, toDispose);
  }
}
