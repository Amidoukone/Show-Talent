import 'dart:async';

import 'package:adfoot/models/video.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';

import 'package:adfoot/widgets/video_manager.dart';

class VideoFocusOrchestrator {
  VideoFocusOrchestrator({
    required this.contextKey,
    required this.videoManager,
    required List<String> urls,
    this.onRequestMore,
    this.disposeWindow = 25,
  }) : _urls = List.of(urls);

  final String contextKey;
  final VideoManager videoManager;
  final Future<void> Function()? onRequestMore;
  final int disposeWindow;

  List<String> _urls;
  bool _isDisposed = false;
  int _requestToken = 0;

  void updateUrls(List<String> urls) {
    _urls = List.of(urls);
  }

  Future<CachedVideoPlayerPlus?> onIndexChanged(int index) async {
    if (_isDisposed) return null;
    if (index < 0 || index >= _urls.length) return null;

    final localToken = ++_requestToken;
    final currentUrl = _urls[index];

    videoManager.preloadSurrounding(
      contextKey,
      _urls.cast<Video>(),
      index,
      activeUrl: currentUrl,
    );

    await videoManager.pauseAllExcept(contextKey, currentUrl);
    if (_isStale(localToken)) return null;

    var player = videoManager.getController(contextKey, currentUrl);
    final ctrl = player?.controller;

    if (ctrl == null || !ctrl.value.isInitialized || ctrl.value.hasError) {
      try {
        player = await videoManager.initializeController(
          contextKey,
          currentUrl,
          autoPlay: true,
          activeUrl: currentUrl,
        );
      } catch (_) {
        return null;
      }
    }

    if (_isStale(localToken)) return player;

    final actualCtrl = player?.controller;
    if (actualCtrl != null &&
        actualCtrl.value.isInitialized &&
        !actualCtrl.value.hasError &&
        !actualCtrl.value.isPlaying) {
      try {
        await actualCtrl.play();
      } catch (_) {}
    }

    if (!_isStale(localToken)) {
      await _disposeFarPlayers(index, localToken);
    }

    if (!_isDisposed &&
        onRequestMore != null &&
        index >= _urls.length - 2) {
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
    if (_urls.length <= disposeWindow || _isStale(token)) return;

    final start =
        (index - disposeWindow ~/ 2).clamp(0, _urls.length).toInt();
    final end = (start + disposeWindow).clamp(0, _urls.length).toInt();

    final keepUrls = _urls.sublist(start, end).toSet();
    final toDispose = _urls.toSet().difference(keepUrls).toList();

    if (toDispose.isEmpty || _isStale(token)) return;

    await videoManager.disposeUrls(contextKey, toDispose);
  }
}