import 'dart:async';

import 'package:adfoot/models/video.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:adfoot/widgets/video_manager.dart';

class VideoFocusOrchestrator {
  VideoFocusOrchestrator({
    required this.contextKey,
    required this.videoManager,
    required List<Video> videos,
    this.onRequestMore,
    this.disposeWindow = 25,
  }) : _videos = List.of(videos);

  final String contextKey;
  final VideoManager videoManager;
  final Future<void> Function()? onRequestMore;
  final int disposeWindow;

  List<Video> _videos;
  bool _isDisposed = false;
  int _requestToken = 0;

  /// Met à jour la liste des vidéos (pagination / refresh)
  void updateVideos(List<Video> videos) {
    _videos = List.of(videos);
  }

  /// Appelé lors du changement de focus (scroll, swipe, etc.)
  Future<CachedVideoPlayerPlus?> onIndexChanged(int index) async {
    if (_isDisposed) return null;
    if (index < 0 || index >= _videos.length) return null;

    final localToken = ++_requestToken;
    final currentVideo = _videos[index];
    final currentUrl = currentVideo.videoUrl;

    /// Préchargement intelligent autour de l’index
    videoManager.preloadSurrounding(
      contextKey,
      _videos,
      index,
      activeUrl: currentUrl,
      useHls: currentVideo.hasHlsSource,
    );

    /// Pause de tous les autres players du contexte
    await videoManager.pauseAllExcept(contextKey, currentUrl);
    if (_isStale(localToken)) return null;

    /// Récupération ou initialisation du player courant
    var player = videoManager.getController(contextKey, currentUrl);
    final ctrl = player?.controller;

    if (ctrl == null || !ctrl.value.isInitialized || ctrl.value.hasError) {
      try {
        player = await videoManager.initializeController(
          contextKey,
          currentUrl,
          sources: currentVideo.sources,
          useHls: currentVideo.hasHlsSource,
          autoPlay: true,
          activeUrl: currentUrl,
        );
      } catch (_) {
        return null;
      }
    }

    if (_isStale(localToken)) return player;

    /// Lecture effective
    final actualCtrl = player?.controller;
    if (actualCtrl != null &&
        actualCtrl.value.isInitialized &&
        !actualCtrl.value.hasError &&
        !actualCtrl.value.isPlaying) {
      try {
        await actualCtrl.play();
      } catch (_) {}
    }

    /// Nettoyage mémoire (disposeWindow)
    if (!_isStale(localToken)) {
      await _disposeFarPlayers(index, localToken);
    }

    /// Pagination anticipée
    if (!_isDisposed &&
        onRequestMore != null &&
        index >= _videos.length - 2) {
      await onRequestMore!();
    }

    return player;
  }

  /// Libération complète du contexte
  Future<void> onDispose() async {
    _isDisposed = true;
    _requestToken++;
    await videoManager.pauseAll(contextKey);
    await videoManager.disposeAllForContext(contextKey);
  }

  bool _isStale(int token) => _isDisposed || token != _requestToken;

  /// Dispose les players trop éloignés de l’index courant
  Future<void> _disposeFarPlayers(int index, int token) async {
    if (_videos.length <= disposeWindow || _isStale(token)) return;

    final start =
        (index - disposeWindow ~/ 2).clamp(0, _videos.length).toInt();
    final end = (start + disposeWindow).clamp(0, _videos.length).toInt();

    final keepUrls = _videos
        .sublist(start, end)
        .map((v) => v.videoUrl)
        .toSet();

    final toDispose = _videos
        .map((v) => v.videoUrl)
        .toSet()
        .difference(keepUrls)
        .toList();

    if (toDispose.isEmpty || _isStale(token)) return;

    await videoManager.disposeUrls(contextKey, toDispose);
  }
}
