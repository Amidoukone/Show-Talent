import 'dart:async';
import 'package:adfoot/utils/video_cache_manager.dart';
import 'package:flutter/material.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:adfoot/widgets/tiktok_video_player.dart';
import 'package:adfoot/models/video.dart';
import 'package:share_plus/share_plus.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SmartVideoPlayer extends StatefulWidget {
  final CachedVideoPlayerPlus? player;
  final Video video;
  final String contextKey;
  final String videoUrl;
  final int currentIndex;
  final List<Video> videoList;
  final bool enableTapToPlay;
  final bool autoPlay;
  final bool showControls;
  final bool showProgressBar;

  const SmartVideoPlayer({
    super.key,
    required this.player,
    required this.video,
    required this.contextKey,
    required this.videoUrl,
    required this.currentIndex,
    required this.videoList,
    required this.enableTapToPlay,
    required this.autoPlay,
    required this.showControls,
    this.showProgressBar = false,
  });

  @override
  State<SmartVideoPlayer> createState() => _SmartVideoPlayerState();
}

class _SmartVideoPlayerState extends State<SmartVideoPlayer> with WidgetsBindingObserver {
  late final VideoManager _videoManager;
  late final ValueNotifier<bool> _showPlayIcon;

  CachedVideoPlayerPlus? _player;
  VideoPlayerController? get _ctrl => _player?.controller;

  bool _hasAutoplayStarted = false;
  bool _hasFirstFrame = false;
  int _attachToken = 0;

  late final VideoController _vc;
  late final Worker _indexWorker; // NEW: observe l’index courant

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _videoManager = VideoManager();
    _showPlayIcon = ValueNotifier(true);

    if (!Get.isRegistered<VideoController>(tag: widget.contextKey)) {
      Get.put(VideoController(contextKey: widget.contextKey), tag: widget.contextKey, permanent: true);
    }
    _vc = Get.find<VideoController>(tag: widget.contextKey);

    // 🔁 Autoplay sur changement d’index global (scroll)
    _indexWorker = ever<int>(_vc.currentIndex, (i) {
      if (!mounted) return;
      if (i == widget.currentIndex) {
        // Cette tuile devient courante -> autoplay
        _maybePlay();
      } else {
        // Cette tuile sort de l’écran -> pause
        _pause();
      }
    });

    _attachOrInitialize(reuse: widget.player);
  }

  @override
  void didUpdateWidget(SmartVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl || oldWidget.player?.controller != widget.player?.controller) {
      _detachListener(oldWidget.player?.controller);
      _hasAutoplayStarted = false;
      _hasFirstFrame = false;
      _attachOrInitialize(reuse: widget.player);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _indexWorker.dispose(); // stop observe
    _setWakelock(false);
    _detachListener(_ctrl);
    _showPlayIcon.dispose();
    super.dispose();
  }

  // lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pause();
      _setWakelock(false);
    } else if (state == AppLifecycleState.resumed) {
      _maybePlay();
      _updateWakelock();
    }
  }

  // attach / init
  Future<void> _attachOrInitialize({CachedVideoPlayerPlus? reuse}) async {
    final localToken = ++_attachToken;

    CachedVideoPlayerPlus? p = reuse ?? _videoManager.getController(widget.contextKey, widget.videoUrl);
    if (p == null) {
      try {
        p = await _videoManager.initializeController(
          widget.contextKey,
          widget.videoUrl,
          autoPlay: false,
          activeUrl: widget.videoUrl,
        );
      } catch (e) {
        debugPrint('[SmartVideoPlayer] init error: $e');
      }
    }
    if (!mounted || localToken != _attachToken) return;

    _bindPlayer(p);

    // Si on arrive déjà comme item courant et autoplay activé -> joue
    if (widget.autoPlay && _vc.currentIndex.value == widget.currentIndex) {
      _maybePlay();
    }
  }

  void _bindPlayer(CachedVideoPlayerPlus? p) {
    _player = p;
    _detachListener(_ctrl);
    _hasFirstFrame = false;

    if (_ctrl != null) {
      _ctrl!.addListener(_onTick);
      if (_ctrl!.value.isInitialized && _ctrl!.value.position > Duration.zero && !_ctrl!.value.isBuffering) {
        _hasFirstFrame = true;
      }
      _showPlayIcon.value = !(_ctrl!.value.isPlaying);
    }
    setState(() {});
    _updateWakelock();
  }

  void _detachListener(VideoPlayerController? ctrl) {
    try {
      ctrl?.removeListener(_onTick);
    } catch (_) {}
  }

  void _onTick() {
    final c = _ctrl;
    if (c == null) return;

    if (!_hasFirstFrame && c.value.isInitialized && !c.value.isBuffering && c.value.position > Duration.zero) {
      setState(() => _hasFirstFrame = true);
    }

    _showPlayIcon.value = !(c.value.isPlaying);

    final isCurrent = _vc.currentIndex.value == widget.currentIndex;
    if (!isCurrent && c.value.isPlaying) {
      c.pause();
    }

    // L’ancienne logique d’autoplay basée uniquement sur les ticks reste,
    // mais le worker d’index garantit maintenant le déclenchement au scroll.
    if (widget.autoPlay && !_hasAutoplayStarted && c.value.isInitialized && !c.value.hasError && !c.value.isPlaying) {
      // _maybePlay(); // (laissé possible mais non indispensable grâce au worker)
    }

    _updateWakelock();
  }

  Future<void> _maybePlay() async {
    final c = _ctrl;
    if (c == null) {
      _setWakelock(false);
      return;
    }

    if (_vc.currentIndex.value != widget.currentIndex) {
      _setWakelock(false);
      return;
    }

    if (!c.value.isInitialized) {
      try {
        await _videoManager.waitUntilInitialized(widget.contextKey, widget.videoUrl);
      } catch (_) {
        _setWakelock(false);
        return;
      }
    }
    if (!c.value.isInitialized || c.value.hasError) {
      _setWakelock(false);
      return;
    }

    if (c.value.position == Duration.zero) {
      await c.seekTo(Duration.zero);
    }

    await _videoManager.pauseAllExcept(widget.contextKey, widget.videoUrl);

    if (!c.value.isPlaying) {
      await c.play();
      _hasAutoplayStarted = true;
    }

    _updateWakelock();
  }

  void _pause() {
    final c = _ctrl;
    if (c == null) {
      _setWakelock(false);
      return;
    }
    if (c.value.isPlaying) {
      c.pause();
    }
    _setWakelock(false);
  }

  // ---- Wakelock helpers ----
  void _updateWakelock() {
    final c = _ctrl;
    final shouldKeepAwake =
        c != null &&
        c.value.isInitialized &&
        c.value.isPlaying &&
        !c.value.isBuffering &&
        (_vc.currentIndex.value == widget.currentIndex);

    _setWakelock(shouldKeepAwake);
  }

  bool _wakelockOn = false;
  Future<void> _setWakelock(bool enable) async {
    if (enable == _wakelockOn) return;
    _wakelockOn = enable;
    try {
      if (enable) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      debugPrint('Wakelock error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoController = Get.find<VideoController>(tag: widget.contextKey);
    final userController = Get.find<UserController>();
    final ctrl = _ctrl;
    final loadState = _videoManager.getLoadState(widget.contextKey, widget.videoUrl);

    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _showPlayIcon,
          builder: (_, showIcon, __) {
            return TiktokVideoPlayer(
              controller: ctrl,
              isPlaying: ctrl?.value.isPlaying ?? false,
              hidePlayPauseIcon: !showIcon,
              showControls: widget.showControls,
              showProgressBar: widget.showProgressBar,
              isBuffering: ctrl?.value.isBuffering ?? false,
              isLoading: loadState == VideoLoadState.loading,
              errorMessage: _getErrorMessage(loadState),
              thumbnailUrl: widget.video.thumbnailUrl,
              hasFirstFrame: _hasFirstFrame,
              onTogglePlayPause: () {
                if (ctrl == null || !ctrl.value.isInitialized) return;
                ctrl.value.isPlaying ? _pause() : _maybePlay();
              },
              onRetry: () async {
                debugPrint('[SmartVideoPlayer] Retry tapped for ${widget.video.videoUrl}');
                await _purgeAndReloadController();
              },
            );
          },
        ),
        if (widget.showControls) _buildActions(context, videoController, userController),
      ],
    );
  }

  String? _getErrorMessage(VideoLoadState? state) {
    switch (state) {
      case VideoLoadState.errorTimeout:
        return 'Chargement trop long';
      case VideoLoadState.errorSource:
        return 'Erreur de lecture';
      default:
        return null;
    }
  }

  Widget _buildActions(
      BuildContext context, VideoController videoController, UserController userController) {
    final user = userController.user;
    if (user == null) return const SizedBox();

    final isOwner = widget.video.uid == user.uid;

    return Positioned(
      right: 10,
      bottom: 70,
      child: Column(
        children: [
          if (isOwner)
            _buildActionButton(
              icon: Icons.delete,
              color: Colors.red,
              label: 'Supprimer',
              onPressed: () => _confirmDelete(context, videoController),
            ),
          _buildActionButton(
            icon: Icons.favorite,
            color: widget.video.likes.contains(user.uid) ? Colors.red : Colors.white,
            label: '${widget.video.likes.length}',
            onPressed: () => _toggleLike(videoController, user.uid),
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            icon: Icons.share,
            color: Colors.white,
            label: '${widget.video.shareCount}',
            onPressed: () => _shareVideo(videoController),
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            icon: Icons.flag,
            color: Colors.white,
            label: '${widget.video.reportCount}',
            onPressed: () => videoController.signalerVideo(widget.video.id, user.uid),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        IconButton(icon: Icon(icon, color: color), onPressed: onPressed),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }

  void _toggleLike(VideoController controller, String userId) {
    if (widget.video.likes.contains(userId)) {
      widget.video.likes.remove(userId);
    } else {
      widget.video.likes.add(userId);
    }
    controller.likeVideo(widget.video.id, userId);
    setState(() {});
  }

  void _confirmDelete(BuildContext context, VideoController controller) {
    Get.dialog(
      AlertDialog(
        title: const Text('Supprimer la vidéo'),
        content: const Text('Confirmer la suppression ?'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              controller.deleteVideo(widget.video.id);
              Get.back();
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareVideo(VideoController controller) async {
    try {
      await Share.share('Regarde cette vidéo : ${widget.video.videoUrl}');
      await controller.partagerVideo(widget.video.id);
    } catch (_) {
      Get.snackbar('Erreur', 'Partage impossible',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> _purgeAndReloadController() async {
    try {
      final file = await VideoCacheManager.getFileIfCached(widget.videoUrl);
      if (file != null && await file.exists()) {
        await file.delete();
        debugPrint("[SmartVideoPlayer] Cache corrompu supprimé pour ${widget.videoUrl}");
      }
    } catch (_) {}
    _hasAutoplayStarted = false;
    _hasFirstFrame = false;
    setState(() {});
    unawaited(_attachOrInitialize(reuse: null));
  }
}
