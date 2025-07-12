import 'package:flutter/material.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:adfoot/widgets/tiktok_video_player.dart';
import 'package:adfoot/models/video.dart';
import 'package:share_plus/share_plus.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';

class SmartVideoPlayer extends StatelessWidget {
  final CachedVideoPlayerPlusController? controller;
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
    required this.controller,
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
  Widget build(BuildContext context) {
    final videoController = Get.find<VideoController>(tag: contextKey);
    final userController = Get.find<UserController>();

    final ctrl = controller;

    // ✅ Gestion dynamique du bouton play/pause
    final hideIcon = ctrl?.value.isPlaying ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        TiktokVideoPlayer(
          controller: ctrl,
          isPlaying: ctrl?.value.isPlaying ?? false,
          hidePlayPauseIcon: hideIcon,
          showControls: showControls,
          showProgressBar: showProgressBar,
          isBuffering: ctrl?.value.isBuffering ?? false,
          isLoading: !(ctrl?.value.isInitialized ?? false),
          errorMessage: ctrl?.value.hasError == true ? 'Erreur de lecture' : null,
          thumbnailUrl: video.thumbnailUrl,
          onTogglePlayPause: () {
            if (ctrl == null || !ctrl.value.isInitialized) return;
            if (ctrl.value.isPlaying) {
              ctrl.pause();
            } else {
              ctrl.play();
            }
          },
          onRetry: () {
            debugPrint('[SmartVideoPlayer] Retry tapped for ${video.videoUrl}');
          },
        ),
        if (showControls) _buildActions(context, videoController, userController),
      ],
    );
  }

  Widget _buildActions(BuildContext context, VideoController videoController, UserController userController) {
    final user = userController.user!;
    final isOwner = video.uid == user.uid;

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
            color: video.likes.contains(user.uid) ? Colors.red : Colors.white,
            label: '${video.likes.length}',
            onPressed: () => _toggleLike(videoController, user.uid),
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            icon: Icons.share,
            color: Colors.white,
            label: '${video.shareCount}',
            onPressed: () => _shareVideo(videoController),
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            icon: Icons.flag,
            color: Colors.white,
            label: '${video.reportCount}',
            onPressed: () => videoController.signalerVideo(video.id, user.uid),
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
    if (video.likes.contains(userId)) {
      video.likes.remove(userId);
    } else {
      video.likes.add(userId);
    }
    controller.likeVideo(video.id, userId);
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
              controller.deleteVideo(video.id);
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
      await Share.share('Regarde cette vidéo : ${video.videoUrl}');
      await controller.partagerVideo(video.id);
    } catch (_) {
      Get.snackbar('Erreur', 'Partage impossible', backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
}
