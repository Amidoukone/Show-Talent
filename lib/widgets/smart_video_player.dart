// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:adfoot/screens/add_video.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:adfoot/utils/video_cache_manager.dart' as custom_cache;
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

  bool _hasFirstFrame = false;
  int _attachToken = 0;

  // ✅ On garde une référence locale (ne jamais refaire Get.find dans build)
  VideoController? _vc;
  Worker? _indexWorker;

  AppLifecycleState _appState = AppLifecycleState.resumed;
  bool _isTryingToPlay = false;
  bool _wakelockOn = false;
  bool _isDisposed = false;

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

    // ✅ GetX: robuste — on essaie de récupérer le controller si présent
    if (Get.isRegistered<VideoController>(tag: widget.contextKey)) {
      _vc = Get.find<VideoController>(tag: widget.contextKey);
    } else {
      // Conserve ton comportement existant (crée si absent)
      _vc = Get.put(
        VideoController(contextKey: widget.contextKey),
        tag: widget.contextKey,
        permanent: true,
      );
    }

    // ✅ Worker protégé (si _vc devient null, on ne crash pas)
    _indexWorker = ever<int>(_vc!.currentIndex, (i) {
      if (!mounted || _isDisposed) return;
      if (i == widget.currentIndex) {
        _scheduleMaybePlay();
      } else {
        _becomePassive();
      }
    });

    _attachOrInitialize(reuse: widget.player);
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    // ✅ stop worker proprement
    try {
      _indexWorker?.dispose();
    } catch (_) {}

    _detachListener(_ctrl);

    _showPlayIcon.dispose();
    _playDebounceTimer?.cancel();
    _stopStallWatchdog();

    // ✅ wakelock off
    unawaited(_setWakelock(false));

    super.dispose();
  }

  @override
  void deactivate() {
    _becomePassive();
    unawaited(_setWakelock(false));
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState = state;
    if (!mounted || _isDisposed) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _becomePassive();
    } else if (state == AppLifecycleState.resumed) {
      if (_isActuallyVisible() && (_vc?.currentIndex.value == widget.currentIndex)) {
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

    if (!mounted || _isDisposed || localToken != _attachToken) return;

    _bindPlayer(p);

    if (widget.autoPlay &&
        (_vc?.currentIndex.value == widget.currentIndex) &&
        _isActuallyVisible()) {
      _scheduleMaybePlay();
    }
  }

  void _bindPlayer(CachedVideoPlayerPlus? p) {
    _detachListener(_ctrl);
    _player = p;
    _hasFirstFrame = false;

    final ctrl = _ctrl;
    if (_isControllerValid(ctrl)) {
      ctrl?.addListener(_onTick);
      _showPlayIcon.value = !(ctrl!.value.isPlaying);
    } else {
      // si pas valide, on force icône "play" visible
      _showPlayIcon.value = true;
    }

    if (mounted && !_isDisposed) setState(() {});
    _updateWakelock();
  }

  bool _isControllerValid(VideoPlayerController? ctrl) {
    try {
      return !_isDisposed && ctrl != null && ctrl.value.isInitialized;
    } catch (_) {
      return false;
    }
  }

  void _detachListener(VideoPlayerController? ctrl) {
    try {
      ctrl?.removeListener(_onTick);
    } catch (_) {}
  }

  void _onTick() {
    if (_isDisposed) return;

    final c = _ctrl;
    if (!_isControllerValid(c)) return;

    // ⚠️ Si le player natif a été détruit en arrière-plan, évite les accès risqués
    final v = c!.value;
    if (v.hasError) {
      _becomePassive();
      return;
    }

    if (!_hasFirstFrame && v.position > Duration.zero && !v.isBuffering) {
      _hasFirstFrame = true;
    }

    _showPlayIcon.value = !(v.isPlaying);

    final shouldBePlaying =
        (_vc?.currentIndex.value == widget.currentIndex) && _isActuallyVisible();

    if (!shouldBePlaying && v.isPlaying) {
      try {
        c.pause();
      } catch (_) {}
    }

    _updateWakelock();
    _kickStallWatchdog();
  }

  void _updateWakelock() {
    final ctrl = _ctrl;
    if (!_isControllerValid(ctrl)) {
      unawaited(_setWakelock(false));
      return;
    }

    final shouldKeepAwake = ctrl!.value.isPlaying &&
        (_vc?.currentIndex.value == widget.currentIndex);

    unawaited(_setWakelock(shouldKeepAwake));
  }

  bool _isActuallyVisible() {
    if (!mounted || _isDisposed) return false;
    if (_appState != AppLifecycleState.resumed) return false;

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    return (_vc?.currentIndex.value == widget.currentIndex);
  }

  void _scheduleMaybePlay() {
    _playDebounceTimer?.cancel();
    _playDebounceTimer = Timer(_playDebounce, _maybePlay);
  }

  Future<void> _maybePlay() async {
    if (_isTryingToPlay || _isDisposed) return;
    _isTryingToPlay = true;

    try {
      final c = _ctrl;
      if (!_isControllerValid(c) || !_isActuallyVisible()) return;

      await _videoManager.pauseAllExcept(widget.contextKey, widget.videoUrl);

      if (!(c?.value.isPlaying ?? false)) {
        try {
          await c?.play();
        } catch (e) {
          debugPrint("⚠️ play error: $e");
        }
      }

      _updateWakelock();
      _kickStallWatchdog(forceRestart: true);
    } finally {
      _isTryingToPlay = false;
    }
  }

  void _becomePassive() {
    final c = _ctrl;
    if (_isControllerValid(c) && (c?.value.isPlaying ?? false)) {
      try {
        c?.pause();
      } catch (_) {}
    }
    unawaited(_setWakelock(false));
    _stopStallWatchdog();
  }

  void _kickStallWatchdog({bool forceRestart = false}) {
    final c = _ctrl;
    if (!_isControllerValid(c)) return;
    if (!(c?.value.isInitialized ?? false) || !(c?.value.isPlaying ?? false)) return;
    if (_stallTimer != null && !forceRestart) return;

    _stallTimer?.cancel();
    _lastKnownPos = c!.value.position;
    _stallStrikes = 0;

    _stallTimer = Timer.periodic(_stallCheckInterval, (_) async {
      if (_isDisposed) {
        _stopStallWatchdog();
        return;
      }

      final v = c.value;
      if (!v.isInitialized || v.hasError || !v.isPlaying) {
        _stopStallWatchdog();
        return;
      }

      if (v.isBuffering) {
        _lastKnownPos = v.position;
        _stallStrikes = 0;
        return;
      }

      if (v.position <= _lastKnownPos) {
        _stallStrikes++;
        if (_stallStrikes >= _stallMaxStrikesBeforeReload) {
          _stallStrikes = 0;
          await _softReloadController();
        }
      } else {
        _stallStrikes = 0;
      }

      _lastKnownPos = v.position;
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
    if (!_isControllerValid(c)) return;
    try {
      await c?.pause();
      await Future.delayed(const Duration(milliseconds: 50));
      if (_isDisposed) return;
      await c?.play();
    } catch (_) {
      await _purgeAndReloadController();
    }
  }

  Future<void> _setWakelock(bool enable) async {
    if (_wakelockOn == enable) return;
    _wakelockOn = enable;
    try {
      enable ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // ✅ IMPORTANT : plus de Get.find dans build (évite crash au retour)
    final videoController = _vc;
    final userController = Get.find<UserController>();

    final ctrl = _ctrl;
    final loadState =
        _videoManager.getLoadState(widget.contextKey, widget.videoUrl);

    // Si jamais _vc est null (cas rare), on affiche seulement la vidéo (UI safe)
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
                if (_isControllerValid(ctrl)) {
                  (ctrl?.value.isPlaying ?? false)
                      ? _becomePassive()
                      : _scheduleMaybePlay();
                }
              },
              onRetry: _purgeAndReloadController,
            );
          },
        ),
        if (widget.showControls && videoController != null)
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

  Widget _animatedActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    VideoController videoController,
    UserController userController,
  ) {
    final user = userController.user;
    if (user == null) return const SizedBox();

    final isOwner = widget.video.uid == user.uid;
    final screenHeight = MediaQuery.of(context).size.height;
    double bottomOffset = screenHeight * 0.22;
    if (bottomOffset < 120) bottomOffset = 120;

    return Positioned(
      right: 10,
      bottom: bottomOffset,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOwner)
            _animatedActionButton(
              icon: Icons.delete,
              color: Colors.red,
              label: 'Supprimer',
              onTap: () => _confirmDelete(context, videoController),
            ),
          if (isOwner) const SizedBox(height: 24),
          _animatedActionButton(
            icon: Icons.favorite,
            color: widget.video.likes.contains(user.uid)
                ? Colors.red
                : Colors.white,
            label: '${widget.video.likes.length}',
            onTap: () => _toggleLike(videoController, user.uid),
          ),
          const SizedBox(height: 24),
          _animatedActionButton(
            icon: Icons.share,
            color: Colors.white,
            label: '${widget.video.shareCount}',
            onTap: () => _shareVideo(videoController),
          ),
          const SizedBox(height: 24),
          _animatedActionButton(
            icon: Icons.flag,
            color: Colors.white,
            label: '${widget.video.reportCount}',
            onTap: () =>
                videoController.signalerVideo(widget.video.id, user.uid),
          ),
          const SizedBox(height: 28),
          if (user.role == 'joueur')
            Column(
              children: [
                FloatingActionButton(
                  heroTag: 'addVideo_${widget.video.id}',
                  mini: true,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 3,
                  onPressed: () async {
                    await _videoManager.pauseAll(widget.contextKey);
                    await _setWakelock(false);
                    final result = await Get.to(() => const AddVideo());
                    if (result == true) {
                      await videoController.refreshVideos();
                    } else {
                      _scheduleMaybePlay();
                    }
                  },
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ajouter',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _toggleLike(VideoController controller, String userId) {
    if (widget.video.likes.contains(userId)) {
      widget.video.likes.remove(userId);
    } else {
      widget.video.likes.add(userId);
    }
    controller.likeVideo(widget.video.id, userId);
    if (mounted && !_isDisposed) setState(() {});
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
      await SharePlus.instance.share(
        ShareParams(text: 'Regarde cette vidéo : ${widget.video.videoUrl}'),
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
        final file =
            await custom_cache.VideoCacheManager.getFileIfCached(widget.videoUrl);
        if (file != null && await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    _hasFirstFrame = false;
    _stopStallWatchdog();
    if (mounted && !_isDisposed) setState(() {});
    unawaited(_attachOrInitialize(reuse: null));
  }
}
