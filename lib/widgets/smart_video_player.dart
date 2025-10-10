import 'dart:async';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart'; // ✅ Import correct de SharePlus

import 'package:adfoot/utils/video_cache_manager.dart';
import 'package:adfoot/widgets/tiktok_video_player.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/widgets/video_manager.dart';

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

class _SmartVideoPlayerState extends State<SmartVideoPlayer>
    with WidgetsBindingObserver {
  late final VideoManager _videoManager;
  late final ValueNotifier<bool> _showPlayIcon;

  CachedVideoPlayerPlus? _player;
  VideoPlayerController? get _ctrl => _player?.controller;

  bool _hasAutoplayStarted = false;
  bool _hasFirstFrame = false;
  int _attachToken = 0;

  late final VideoController _vc;
  late final Worker _indexWorker;

  AppLifecycleState _appState = AppLifecycleState.resumed;
  bool _isTryingToPlay = false;
  bool _wakelockOn = false;

  Timer? _playDebounceTimer;
  static const Duration _playDebounce = Duration(milliseconds: 120);

  Timer? _stallTimer;
  Duration _lastKnownPos = Duration.zero;
  int _stallStrikes = 0;
  static const Duration _stallCheckInterval = Duration(milliseconds: 700);
  static const int _stallMaxStrikesBeforeReload = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _videoManager = VideoManager();
    _showPlayIcon = ValueNotifier<bool>(true);

    if (!Get.isRegistered<VideoController>(tag: widget.contextKey)) {
      Get.put(
        VideoController(contextKey: widget.contextKey),
        tag: widget.contextKey,
        permanent: true,
      );
    }
    _vc = Get.find<VideoController>(tag: widget.contextKey);

    _indexWorker = ever<int>(_vc.currentIndex, (i) {
      if (!mounted) return;
      if (i == widget.currentIndex) {
        _scheduleMaybePlay();
      } else {
        _becomePassive();
      }
    });

    _attachOrInitialize(reuse: widget.player);
  }

  @override
  void didUpdateWidget(SmartVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlChanged = oldWidget.videoUrl != widget.videoUrl;
    final controllerChanged =
        oldWidget.player?.controller != widget.player?.controller;

    if (urlChanged || controllerChanged) {
      _detachListener(oldWidget.player?.controller);
      _stopStallWatchdog();
      _hasAutoplayStarted = false;
      _hasFirstFrame = false;
      _attachOrInitialize(reuse: widget.player);
    } else {
      if (!_isActuallyVisible()) {
        _becomePassive();
      } else if (widget.autoPlay &&
          _vc.currentIndex.value == widget.currentIndex &&
          _isActuallyVisible()) {
        _scheduleMaybePlay();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _indexWorker.dispose();
    _setWakelock(false);
    _detachListener(_ctrl);
    _showPlayIcon.dispose();
    _playDebounceTimer?.cancel();
    _stopStallWatchdog();
    super.dispose();
  }

  @override
  void deactivate() {
    _becomePassive();
    _setWakelock(false);
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState = state;
    if (!mounted) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _becomePassive();
      _setWakelock(false);
    } else if (state == AppLifecycleState.resumed) {
      if (_isActuallyVisible() &&
          _vc.currentIndex.value == widget.currentIndex) {
        _scheduleMaybePlay();
      }
    }
  }

  Future<void> _attachOrInitialize({CachedVideoPlayerPlus? reuse}) async {
    final localToken = ++_attachToken;
    CachedVideoPlayerPlus? p =
        reuse ?? _videoManager.getController(widget.contextKey, widget.videoUrl);

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

    if (widget.autoPlay &&
        _vc.currentIndex.value == widget.currentIndex &&
        _isActuallyVisible()) {
      _scheduleMaybePlay();
    }
  }

  void _bindPlayer(CachedVideoPlayerPlus? p) {
    _player = p;
    _detachListener(_ctrl);
    _hasFirstFrame = false;

    final ctrl = _ctrl;
    if (ctrl != null) {
      ctrl.addListener(_onTick);

      if (ctrl.value.isInitialized &&
          ctrl.value.position > Duration.zero &&
          !ctrl.value.isBuffering) {
        _hasFirstFrame = true;
      }

      if (_vc.currentIndex.value != widget.currentIndex) {
        _safeSetVolume(0.0);
      }

      final newIcon = !(ctrl.value.isPlaying);
      if (newIcon != _showPlayIcon.value) {
        _showPlayIcon.value = newIcon;
      }
    }

    if (mounted) setState(() {});
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

    if (!_hasFirstFrame &&
        c.value.isInitialized &&
        !c.value.isBuffering &&
        c.value.position > Duration.zero) {
      if (mounted) setState(() => _hasFirstFrame = true);
    }

    final newIcon = !(c.value.isPlaying);
    if (newIcon != _showPlayIcon.value) {
      _showPlayIcon.value = newIcon;
    }

    final shouldBePlaying =
        _vc.currentIndex.value == widget.currentIndex && _isActuallyVisible();
    if (!shouldBePlaying && c.value.isPlaying) {
      c.pause();
      _safeSetVolume(0.0);
      _hasAutoplayStarted = false;
    }

    if (!c.value.isPlaying || c.value.hasError) {
      _hasAutoplayStarted = false;
    }

    _updateWakelock();
    _kickStallWatchdog();
  }

  bool _isActuallyVisible() {
    if (!mounted) return false;
    if (_appState != AppLifecycleState.resumed) return false;

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    return _vc.currentIndex.value == widget.currentIndex;
  }

  void _scheduleMaybePlay() {
    _playDebounceTimer?.cancel();
    _playDebounceTimer = Timer(_playDebounce, _maybePlay);
  }

  Future<void> _maybePlay() async {
    if (_isTryingToPlay) return;
    _isTryingToPlay = true;

    try {
      final c = _ctrl;
      if (c == null || !_isActuallyVisible()) {
        _setWakelock(false);
        return;
      }

      if (_hasAutoplayStarted && c.value.isPlaying) {
        _updateWakelock();
        return;
      }

      if (!c.value.isInitialized) {
        try {
          await _videoManager.waitUntilInitialized(
              widget.contextKey, widget.videoUrl);
        } catch (_) {
          _setWakelock(false);
          return;
        }
      }

      if (!c.value.isInitialized || c.value.hasError) {
        _setWakelock(false);
        return;
      }

      await _videoManager.pauseAllExcept(widget.contextKey, widget.videoUrl);
      _safeSetVolume(1.0);

      if (c.value.position == Duration.zero) {
        try {
          await c.seekTo(const Duration(milliseconds: 50));
        } catch (_) {}
      }

      if (!c.value.isPlaying) {
        await c.play();
        _hasAutoplayStarted = true;
      }

      _updateWakelock();
      _kickStallWatchdog(forceRestart: true);
    } finally {
      _isTryingToPlay = false;
    }
  }

  void _becomePassive() {
    final c = _ctrl;
    if (c != null) {
      if (c.value.isPlaying) {
        try {
          c.pause();
        } catch (_) {}
      }
      _safeSetVolume(0.0);
    }
    _hasAutoplayStarted = false;
    _setWakelock(false);
    _stopStallWatchdog();
  }

  void _safeSetVolume(double v) {
    final c = _ctrl;
    if (c == null) return;
    try {
      if (c.value.isInitialized) {
        c.setVolume(v.clamp(0.0, 1.0));
      }
    } catch (_) {}
  }

  void _updateWakelock() {
    final c = _ctrl;
    final shouldKeepAwake = c != null &&
        c.value.isInitialized &&
        c.value.isPlaying &&
        !c.value.isBuffering &&
        _isActuallyVisible();
    _setWakelock(shouldKeepAwake);
  }

  Future<void> _setWakelock(bool enable) async {
    if (_wakelockOn == enable) return;
    _wakelockOn = enable;
    try {
      enable ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (e) {
      debugPrint('Wakelock error: $e');
    }
  }

  void _kickStallWatchdog({bool forceRestart = false}) {
    final c = _ctrl;
    if (c == null) return;

    if (!c.value.isInitialized || !c.value.isPlaying) {
      _stopStallWatchdog();
      return;
    }

    if (_stallTimer != null && !forceRestart) return;

    _stallTimer?.cancel();
    _lastKnownPos = c.value.position;
    _stallStrikes = 0;

    _stallTimer = Timer.periodic(_stallCheckInterval, (_) async {
      final cc = _ctrl;
      if (cc == null) {
        _stopStallWatchdog();
        return;
      }

      final v = cc.value;
      if (!v.isInitialized || v.hasError) {
        _stopStallWatchdog();
        return;
      }

      if (!v.isPlaying) {
        _stopStallWatchdog();
        return;
      }

      if (v.isBuffering) {
        _lastKnownPos = v.position;
        _stallStrikes = 0;
        return;
      }

      final pos = v.position;
      final advanced = pos > _lastKnownPos;
      _lastKnownPos = pos;

      if (!advanced) {
        _stallStrikes++;
        if (_stallStrikes == 2) {
          try {
            await cc.seekTo(pos + const Duration(milliseconds: 1));
          } catch (_) {}
        } else if (_stallStrikes >= _stallMaxStrikesBeforeReload) {
          _stallStrikes = 0;
          await _softReloadController();
        }
      } else {
        _stallStrikes = 0;
      }
    });
  }

  void _stopStallWatchdog() {
    _stallTimer?.cancel();
    _stallTimer = null;
    _stallStrikes = 0;
    _lastKnownPos = Duration.zero;
  }

  Future<void> _softReloadController() async {
    final c = _ctrl;
    if (c == null) return;
    try {
      await c.pause();
      await Future.delayed(const Duration(milliseconds: 50));
      await c.play();
      _hasAutoplayStarted = true;
    } catch (_) {
      await _purgeAndReloadController();
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoController = Get.find<VideoController>(tag: widget.contextKey);
    final userController = Get.find<UserController>();
    final ctrl = _ctrl;
    final loadState =
        _videoManager.getLoadState(widget.contextKey, widget.videoUrl);

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
                if (!widget.enableTapToPlay) return;
                if (ctrl == null || !ctrl.value.isInitialized) return;
                if (ctrl.value.isPlaying) {
                  _becomePassive();
                } else {
                  _scheduleMaybePlay();
                }
              },
              onRetry: () async {
                debugPrint(
                    '[SmartVideoPlayer] Retry tapped for ${widget.video.videoUrl}');
                await _purgeAndReloadController();
              },
            );
          },
        ),
        if (widget.showControls)
          _buildActions(context, videoController, userController),
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

  Widget _buildActions(BuildContext context, VideoController videoController,
      UserController userController) {
    final user = userController.user;
    if (user == null) return const SizedBox();

    final isOwner = widget.video.uid == user.uid;

    // 🔥 Décalage dynamique pour éviter tout chevauchement avec l’avatar + bouton + (placés dans HomeScreen)
    final screenHeight = MediaQuery.of(context).size.height;
    double bottomOffset = screenHeight * 0.22; // ~22% de la hauteur écran
    if (bottomOffset < 120) bottomOffset = 120; // garde un minimum sur petits écrans

    return Positioned(
      right: 10,
      bottom: bottomOffset,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOwner)
            _buildActionButton(
              icon: Icons.delete,
              color: Colors.red,
              label: 'Supprimer',
              onPressed: () => _confirmDelete(context, videoController),
            ),
          if (isOwner) const SizedBox(height: 24),

          _buildActionButton(
            icon: Icons.favorite,
            color: widget.video.likes.contains(user.uid)
                ? Colors.red
                : Colors.white,
            label: '${widget.video.likes.length}',
            onPressed: () => _toggleLike(videoController, user.uid),
          ),
          const SizedBox(height: 24),

          _buildActionButton(
            icon: Icons.share,
            color: Colors.white,
            label: '${widget.video.shareCount}',
            onPressed: () => _shareVideo(videoController),
          ),
          const SizedBox(height: 24),

          _buildActionButton(
            icon: Icons.flag,
            color: Colors.white,
            label: '${widget.video.reportCount}',
            onPressed: () =>
                videoController.signalerVideo(widget.video.id, user.uid),
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
        IconButton(icon: Icon(icon, color: color, size: 30), onPressed: onPressed),
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
      // ✅ Nouvelle API SharePlus
      await SharePlus.instance.share(
        ShareParams(
          text: 'Regarde cette vidéo : ${widget.video.videoUrl}',
        ),
      );
      await controller.partagerVideo(widget.video.id);
    } catch (_) {
      Get.snackbar(
        'Erreur',
        'Partage impossible',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _purgeAndReloadController() async {
    if (!kIsWeb) {
      try {
        final file = await VideoCacheManager.getFileIfCached(widget.videoUrl);
        if (file != null && await file.exists()) {
          await file.delete();
          debugPrint(
              "[SmartVideoPlayer] Cache corrompu supprimé pour ${widget.video.videoUrl}");
        }
      } catch (_) {}
    }
    _hasAutoplayStarted = false;
    _hasFirstFrame = false;
    _stopStallWatchdog();
    if (mounted) setState(() {});
    unawaited(_attachOrInitialize(reuse: null));
  }
}
