import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';

class SmartVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final Video video;
  final int currentIndex;
  final RxList<Video> videoList;
  final bool enableTapToPlay;
  final bool showControls;
  final bool autoPlay;
  final bool showProgressBar;
  final VoidCallback? onVideoTap;

  SmartVideoPlayer({
    Key? key,
    required this.videoUrl,
    required this.video,
    required this.currentIndex,
    required this.videoList,
    required this.enableTapToPlay,
    required this.showControls,
    required this.autoPlay,
    this.showProgressBar = false,
    this.onVideoTap,
  }) : super(key: ValueKey(videoUrl));

  @override
  State<SmartVideoPlayer> createState() => _SmartVideoPlayerState();
}

class _SmartVideoPlayerState extends State<SmartVideoPlayer> {
  final videoController = Get.find<VideoController>();
  final userController = Get.find<UserController>();

  CachedVideoPlayerPlusController? _controller;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _hidePlayPauseIcon = false;
  String? _errorMessage;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _controller = CachedVideoPlayerPlusController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller!.initialize();
      _controller!.setLooping(true);
      _controller!.addListener(_onControllerUpdate);

      if (widget.autoPlay) {
        await _controller!.play();
        _isPlaying = true;
        _hidePlayPauseIcon = true;
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Erreur de lecture vidéo';
        });
      }
    }
  }

  void _onControllerUpdate() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return;
    final playingNow = _controller!.value.isPlaying;
    if (_isPlaying != playingNow) {
      setState(() {
        _isPlaying = playingNow;
        if (playingNow && widget.showControls) {
          _hidePlayPauseIcon = true;
        }
      });
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized || _controller!.value.hasError) return;
    if (_isPlaying) {
      _controller!.pause();
      setState(() => _hidePlayPauseIcon = false);
    } else {
      _controller!.play();
      setState(() => _hidePlayPauseIcon = true);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(widget.video.id),
      onVisibilityChanged: (info) {
        final fraction = info.visibleFraction;
        if (fraction > 0.3 && !_visible) {
          _visible = true;
          _controller?.play();
        } else if (fraction <= 0.3 && _visible) {
          _visible = false;
          _controller?.pause();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_isLoading) _buildLoadingThumbnail(),
          if (_errorMessage != null) _buildError(),
          if (_controller != null &&
              _controller!.value.isInitialized &&
              !_controller!.value.hasError)
            _buildVideoPlayer(),
          if (widget.showControls && !_hidePlayPauseIcon)
            _buildPlayPauseButton(),
          if (widget.showControls || widget.showProgressBar)
            _buildProgressBar(),
          if (widget.showControls) _buildActions(),
        ],
      ),
    );
  }

  Widget _buildLoadingThumbnail() {
    return Image.network(
      widget.video.thumbnailUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image, size: 60, color: Colors.white),
      ),
    );
  }

  Widget _buildError() {
    return const Center(
      child: Text(
        'Erreur de lecture',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final size = _controller!.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return _buildLoadingThumbnail();
    }

    return GestureDetector(
      onTap: () {
        if (widget.showControls && widget.enableTapToPlay) {
          _togglePlayPause();
        } else if (widget.onVideoTap != null) {
          widget.onVideoTap!();
        }
      },
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: CachedVideoPlayerPlus(_controller!),
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return Center(
      child: IconButton(
        iconSize: 60,
        icon: Icon(
          _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
          color: Colors.white.withOpacity(0.8),
        ),
        onPressed: _togglePlayPause,
      ),
    );
  }

  Widget _buildProgressBar() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: VideoProgressIndicator(
        _controller!,
        allowScrubbing: true,
        colors: const VideoProgressColors(
          playedColor: Colors.green,
          bufferedColor: Colors.white38,
          backgroundColor: Colors.white24,
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
            onPressed: () => _shareVideo(widget.videoUrl),
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
        IconButton(
          icon: Icon(icon, color: color),
          onPressed: onPressed,
        ),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
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
        content: const Text('Confirmer la suppression ?'),
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
      await Share.share('Regarde cette vidéo : $videoUrl');
      await videoController.partagerVideo(widget.video.id, videoUrl);
    } catch (_) {
      Get.snackbar('Erreur', 'Partage impossible',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
}
