import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/widgets/video_manager.dart';

class SmartVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final Video video;
  final bool enableTapToPlay;

  const SmartVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.video,
    this.enableTapToPlay = true,
  });

  @override
  State<SmartVideoPlayer> createState() => _SmartVideoPlayerState();
}

class _SmartVideoPlayerState extends State<SmartVideoPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  final VideoManager _videoManager = VideoManager();
  final videoController = Get.put(VideoController());
  final userController = Get.find<UserController>();

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isConnected = true;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_fadeController);
    _checkConnectionAndInitVideo();
  }

  Future<void> _checkConnectionAndInitVideo() async {
    final result = await Connectivity().checkConnectivity();
    if (result != ConnectivityResult.none) {
      try {
        _controller = await _videoManager.getController(widget.videoUrl);
        setState(() {
          _isConnected = true;
          _isInitialized = true;
        });
        _fadeController.forward();

        if (mounted && _controller!.value.isInitialized && _isVisible) {
          _controller!.play();
        }
      } on SocketException catch (_) {
        setState(() => _isConnected = false);
      } catch (_) {
        setState(() => _isConnected = false);
      }
    } else {
      setState(() => _isConnected = false);
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConnected) return _buildNoInternet();

    return VisibilityDetector(
      key: Key(widget.videoUrl),
      onVisibilityChanged: (info) {
        _isVisible = info.visibleFraction > 0.9;
        if (_isInitialized && _isVisible) {
          _videoManager.play(widget.videoUrl);
        } else if (_isInitialized) {
          _controller?.pause();
        }
      },
      child: !_isInitialized || _controller == null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  widget.video.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Icon(Icons.broken_image, color: Colors.white, size: 60),
                    ),
                  ),
                ),
                const Center(child: CircularProgressIndicator()),
              ],
            )
          : FadeTransition(
              opacity: _fadeAnimation,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildVideo(),
                  _buildActions(),
                  _buildProgressBar(),
                ],
              ),
            ),
    );
  }

  Widget _buildVideo() {
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _controller!.value.size.width,
        height: _controller!.value.size.height,
        child: GestureDetector(
          onTap: widget.enableTapToPlay
              ? () {
                  _controller!.value.isPlaying
                      ? _controller!.pause()
                      : _controller!.play();
                }
              : null,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }

  Widget _buildActions() {
    final user = userController.user!;
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
              onPressed: _confirmDelete,
            ),
          _buildActionButton(
            icon: Icons.favorite,
            color: widget.video.likes.contains(user.uid) ? Colors.red : Colors.white,
            label: '${widget.video.likes.length}',
            onPressed: () => _toggleLike(user.uid),
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            icon: Icons.share,
            color: Colors.white,
            label: '${widget.video.shareCount}',
            onPressed: () => _shareVideo(widget.video.videoUrl),
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

  Widget _buildProgressBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: VideoProgressIndicator(
        _controller!,
        allowScrubbing: false,
        padding: EdgeInsets.zero,
        colors: const VideoProgressColors(
          playedColor: Colors.green,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
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
        IconButton(
          icon: Icon(icon, color: color, size: 34),
          onPressed: onPressed,
        ),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }

  Widget _buildNoInternet() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: Colors.white, size: 50),
            SizedBox(height: 10),
            Text('Pas de connexion Internet',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
      ),
    );
  }

  void _toggleLike(String userId) {
    setState(() {
      if (widget.video.likes.contains(userId)) {
        widget.video.likes.remove(userId);
      } else {
        widget.video.likes.add(userId);
      }
    });
    videoController.likeVideo(widget.video.id, userId);
  }

  void _confirmDelete() {
    Get.dialog(
      AlertDialog(
        title: const Text('Supprimer la vidéo'),
        content: const Text('Confirmer la suppression de cette vidéo ?'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              videoController.deleteVideo(widget.video.id);
              Get.back();
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareVideo(String videoUrl) async {
    try {
      await Share.share(
        'Découvrez cette vidéo sur AD.FOOT : $videoUrl',
        subject: 'Vidéo partagée depuis AD.FOOT',
      );
      await videoController.partagerVideo(widget.video.id, videoUrl);
    } catch (e) {
      Get.snackbar(
        'Erreur',
        'Partage impossible',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }
}
