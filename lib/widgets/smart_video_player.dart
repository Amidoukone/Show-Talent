import 'dart:async';
import 'package:adfoot/utils/video_cache_manager.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/widgets/tiktok_video_player.dart';
import 'package:adfoot/models/video.dart';

class SmartVideoPlayer extends StatefulWidget {
  final String contextKey;
  final String videoUrl;
  final Video video;
  final int currentIndex;
  final List<Video> videoList;
  final bool enableTapToPlay;
  final bool showControls;
  final bool autoPlay;
  final bool showProgressBar;
  final VoidCallback? onVideoTap;

  const SmartVideoPlayer({
    super.key,
    required this.contextKey,
    required this.videoUrl,
    required this.video,
    required this.currentIndex,
    required this.videoList,
    required this.enableTapToPlay,
    required this.showControls,
    required this.autoPlay,
    this.showProgressBar = false,
    this.onVideoTap,
  });

  @override
  State<SmartVideoPlayer> createState() => _SmartVideoPlayerState();
}

class _SmartVideoPlayerState extends State<SmartVideoPlayer> {
  late final VideoController videoController;
  late final UserController userController;
  final videoManager = VideoManager();

  CachedVideoPlayerPlusController? _controller;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _isBuffering = false;
  bool _hidePlayPause = false;
  bool _visible = false;
  String? _errorMessage;
  late final int _index;
  Timer? _debounce;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    videoController = Get.find<VideoController>(tag: widget.contextKey);
    userController = Get.find<UserController>();
    _index = widget.currentIndex;
    _initialize();
  }

  Future<void> _initialize() async {
    if (_isDisposed) return;

    setState(() => _isLoading = true);

    videoManager.preloadSurrounding(
      widget.contextKey,
      widget.videoList.map((v) => v.videoUrl).toList(),
      _index,
    );

    try {
      final existingCtrl =
          videoManager.getController(widget.contextKey, widget.videoUrl);
      _controller = existingCtrl ??
          await videoManager.initializeController(
              widget.contextKey, widget.videoUrl);

      if (_isDisposed || !mounted) return;

      _controller!.addListener(_onUpdate);

      if (widget.autoPlay && _visible) {
        _safePlay();
      }

      _errorMessage = null;
    } on TimeoutException {
      _errorMessage = 'Temps d’attente dépassé. Vérifie ta connexion.';
    } catch (e) {
      _errorMessage = 'Erreur de lecture.';
      debugPrint('Erreur vidéo : $e');
      try {
        await VideoCacheManager().removeFile(widget.videoUrl);
      } catch (_) {}
    }

    if (!_isDisposed && mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _onUpdate() {
    if (_isDisposed || _controller == null || !_controller!.value.isInitialized) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (_isDisposed || !mounted) return;
      final v = _controller!.value;
      final playing = v.isPlaying;
      final buffering = v.isBuffering;
      if (_isPlaying != playing || _isBuffering != buffering) {
        if (!_isDisposed && mounted) {
          setState(() {
            _isPlaying = playing;
            _isBuffering = buffering;
            if (playing && widget.showControls) _hidePlayPause = true;
          });
        }
      }
    });
  }

  void _togglePlayPause() {
    if (_isDisposed || _controller == null || !_controller!.value.isInitialized) {
      return;
    }
    _controller!.value.isPlaying ? _safePause() : _safePlay();
  }

  void _safePlay() {
    if (_isDisposed || _controller == null) return;
    if (_controller!.value.isInitialized &&
        !_controller!.value.hasError &&
        !_controller!.value.isPlaying) {
      _controller!.play();
    }
  }

  void _safePause() {
    if (_isDisposed || _controller == null) return;
    if (_controller!.value.isInitialized &&
        !_controller!.value.hasError &&
        _controller!.value.isPlaying) {
      _controller!.pause();
    }
  }

  void _retry() {
    if (_isDisposed) return;
    _controller?.removeListener(_onUpdate);
    _initialize();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _debounce?.cancel();
    _controller?.removeListener(_onUpdate);
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(widget.video.id),
      onVisibilityChanged: (info) {
        if (_isDisposed) return;
        final vis = info.visibleFraction > 0.3;
        if (vis && !_visible && videoController.currentIndex.value == _index) {
          _visible = true;
          _safePlay();
        } else if ((!vis || videoController.currentIndex.value != _index) &&
            _visible) {
          _visible = false;
          _safePause();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          TiktokVideoPlayer(
            controller: _controller,
            isPlaying: _isPlaying,
            hidePlayPauseIcon: _hidePlayPause,
            showControls: widget.showControls,
            showProgressBar: widget.showProgressBar,
            isBuffering: _isBuffering,
            isLoading: _isLoading,
            errorMessage: _errorMessage,
            thumbnailUrl: widget.video.thumbnailUrl,
            onTogglePlayPause: _togglePlayPause,
            onRetry: _retry,
          ),
          if (widget.showControls) _buildActions(),
        ],
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
            onPressed: () => _shareVideo(widget.videoUrl),
          ),
          const SizedBox(height: 16),
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
        IconButton(icon: Icon(icon, color: color), onPressed: onPressed),
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
      await videoController.partagerVideo(widget.video.id);
    } catch (_) {
      Get.snackbar('Erreur', 'Partage impossible',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
}
