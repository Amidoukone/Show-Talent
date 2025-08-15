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

class _SmartVideoPlayerState extends State<SmartVideoPlayer> {
  late final VideoManager _videoManager;
  late final ValueNotifier<bool> _showPlayIcon;
  bool _hasAutoplayStarted = false;
  VideoPlayerController? _attachedController;

  @override
  void initState() {
    super.initState();
    _videoManager = VideoManager();
    _showPlayIcon = ValueNotifier(true);
    _attachListener(widget.player?.controller);
  }

  @override
  void didUpdateWidget(SmartVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player?.controller != widget.player?.controller) {
      _detachListener(oldWidget.player?.controller);
      _attachListener(widget.player?.controller);
      _hasAutoplayStarted = false;
    }
  }

  void _attachListener(VideoPlayerController? ctrl) {
    _attachedController = ctrl;
    if (ctrl != null) {
      ctrl.addListener(_controllerListener);
      _showPlayIcon.value = !(ctrl.value.isPlaying);
      if (widget.autoPlay && ctrl.value.isInitialized && !ctrl.value.isPlaying) {
        ctrl.play();
        _hasAutoplayStarted = true;
      }
    }
  }

  void _detachListener(VideoPlayerController? ctrl) {
    ctrl?.removeListener(_controllerListener);
  }

  Future<void> _controllerListener() async {
    final ctrl = widget.player?.controller;
    if (!mounted || ctrl == null) return;

    if (!ctrl.value.isInitialized || ctrl.value.hasError) {
      await _purgeAndReloadController();
      return;
    }

    final isPlaying = ctrl.value.isPlaying;
    _showPlayIcon.value = !isPlaying;

    if (widget.autoPlay &&
        !_hasAutoplayStarted &&
        ctrl.value.isInitialized &&
        !ctrl.value.hasError &&
        !isPlaying) {
      await ctrl.play();
      _hasAutoplayStarted = true;
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

    Get.find<VideoController>(tag: widget.contextKey);
    setState(() {
      _hasAutoplayStarted = false;
    });
  }

  @override
  void dispose() {
    _detachListener(_attachedController);
    _showPlayIcon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoController = Get.find<VideoController>(tag: widget.contextKey);
    final userController = Get.find<UserController>();
    final ctrl = widget.player?.controller;
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
              onTogglePlayPause: () {
                if (ctrl == null || !ctrl.value.isInitialized) return;
                ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
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
}
