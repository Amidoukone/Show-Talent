import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:adfoot/models/video.dart';
import 'package:share_plus/share_plus.dart';

class SmartVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final Video video;
  final bool enableTapToPlay;
  final int currentIndex;
  final List<Video> videoList;

  const SmartVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.video,
    required this.currentIndex,
    required this.videoList,
    this.enableTapToPlay = true,
  });

  @override
  State<SmartVideoPlayer> createState() => _SmartVideoPlayerState();
}

class _SmartVideoPlayerState extends State<SmartVideoPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  final VideoManager _videoManager = VideoManager();
  final videoController = Get.put(VideoController());
  final userController = Get.find<UserController>();

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isConnected = true;
  bool _isVisible = false;
  bool _hasInit = false;
  String? _errorMessage;

  late String effectiveUrl;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_fadeController);

    effectiveUrl = widget.video.hlsUrl ?? '';
  }

  Future<void> _initVideo() async {
    if (_hasInit) return;
    _hasInit = true;

    final result = await Connectivity().checkConnectivity();
    if (result != ConnectivityResult.none) {
      if (widget.video.hlsUrl == null || widget.video.hlsUrl!.isEmpty) {
        setState(() {
          _isConnected = false;
          _errorMessage = 'Vidéo non disponible (conversion en cours...)';
        });
        return;
      }

      try {
        final controller = await _videoManager.getController(widget.video.hlsUrl!);
        if (!mounted) return;

        setState(() {
          _controller = controller;
          _isInitialized = true;
          _isConnected = true;
          _errorMessage = null;
          effectiveUrl = widget.video.hlsUrl!;
        });

        _fadeController.forward();

        if (_isVisible) {
          _videoManager.play(effectiveUrl);
        }

        _preloadNextVideo();
      } catch (e) {
        setState(() {
          _isConnected = false;
          _errorMessage = 'Lecture impossible (HLS)';
        });
      }
    } else {
      setState(() {
        _isConnected = false;
        _errorMessage = 'Pas de connexion Internet';
      });
    }
  }

  void _preloadNextVideo() {
    final nextIndex = widget.currentIndex + 1;
    final secondNextIndex = widget.currentIndex + 2;

    if (nextIndex < widget.videoList.length) {
      final nextVideo = widget.videoList[nextIndex];
      final nextUrl = nextVideo.hlsUrl ?? '';
      if (nextUrl.isNotEmpty) _videoManager.preload(nextUrl);
    }

    if (secondNextIndex < widget.videoList.length) {
      final secondNextVideo = widget.videoList[secondNextIndex];
      final secondNextUrl = secondNextVideo.hlsUrl ?? '';
      if (secondNextUrl.isNotEmpty) _videoManager.preload(secondNextUrl);
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _videoManager.releaseController(effectiveUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(widget.video.id),
      onVisibilityChanged: (info) {
        final visible = info.visibleFraction > 0.6;
        _isVisible = visible;

        if (!_isInitialized) {
          _initVideo();
        } else {
          if (visible) {
            _videoManager.play(effectiveUrl);
          } else {
            _videoManager.pause(effectiveUrl);
          }
        }
      },
      child: !_isConnected
          ? _buildErrorWidget()
          : !_isInitialized || _controller == null
              ? _buildLoadingThumbnail()
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

  Widget _buildLoadingThumbnail() {
    return Stack(
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
                  if (_controller!.value.isPlaying) {
                    _controller!.pause();
                  } else {
                    _controller!.play();
                  }
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
            color: widget.video.likes.contains(user.uid)
                ? Colors.red
                : Colors.white,
            label: '${widget.video.likes.length}',
            onPressed: () => _toggleLike(user.uid),
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            icon: Icons.share,
            color: Colors.white,
            label: '${widget.video.shareCount}',
            onPressed: () => _shareVideo(effectiveUrl),
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

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.white, size: 50),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? 'Erreur de lecture vidéo',
            style: const TextStyle(color: Colors.white, fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ],
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
    } catch (_) {
      Get.snackbar(
        'Erreur',
        'Partage impossible',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }
}
