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
  }) : _videos = List.of(videos);

  final String contextKey;
  final VideoManager videoManager;
  final Future<void> Function()? onRequestMore;
  final int disposeWindow;

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

  Future<void> onDispose() async {
    _isDisposed = true;
    _requestToken++;
    await videoManager.pauseAll(contextKey);
    await videoManager.disposeAllForContext(contextKey);
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
