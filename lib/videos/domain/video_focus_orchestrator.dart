import 'dart:async';

import 'package:adfoot/models/video.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';

class VideoFocusOrchestrator {
  VideoFocusOrchestrator({
    required this.contextKey,
    required this.videoManager,
    required List<Video> videos,
    this.onRequestMore,
    this.useHlsForVideo,
    this.disposeWindow = 25,
  }) : _videos = List.of(videos);

  final String contextKey;
  final VideoManager videoManager;
  final Future<void> Function()? onRequestMore;
  final bool Function(Video video)? useHlsForVideo;
  final int disposeWindow;

  List<Video> _videos;
  bool _isDisposed = false;
  int _requestToken = 0;
  int? _lastFocusedIndex;

  bool _useHls(Video video) => useHlsForVideo?.call(video) ?? false;

  void updateVideos(List<Video> videos) {
    _videos = List.of(videos);
  }

  Future<CachedVideoPlayerPlus?> onIndexChanged(int index) async {
    if (_isDisposed) return null;
    if (index < 0 || index >= _videos.length) return null;

    final localToken = ++_requestToken;
    final currentVideo = _videos[index];
    final currentUrl = currentVideo.videoUrl;
    final requestHls = _useHls(currentVideo);
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
      requestedHls: requestHls,
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
          useHls: requestHls,
          autoPlay: true,
          activeUrl: currentUrl,
        );
      } catch (_) {
        return null;
      }
    }

    if (_isStale(localToken)) return player;

    final actualCtrl = player?.controller;
    bool shouldPlay = false;
    try {
      shouldPlay = actualCtrl != null &&
          actualCtrl.value.isInitialized &&
          !actualCtrl.value.hasError &&
          !actualCtrl.value.isPlaying;
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
          useHls: requestHls,
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
