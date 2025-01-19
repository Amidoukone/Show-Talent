import 'package:flutter/material.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:video_player/video_player.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:adfoot/screens/full_screen_video.dart';
import 'package:share_plus/share_plus.dart';

class TikTokVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final Video video;
  final VideoController videoController;
  final String userId;

  const TikTokVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.video,
    required this.videoController,
    required this.userId, required bool enableTapToPlayPause,
  });

  @override
  _TikTokVideoPlayerState createState() => _TikTokVideoPlayerState();
}

class _TikTokVideoPlayerState extends State<TikTokVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  Future<void> _initializeVideoPlayer() async {
    try {
      final file = await DefaultCacheManager().getSingleFile(widget.videoUrl);
      _controller = VideoPlayerController.file(file)
        ..addListener(() {
          if (_controller.value.hasError) {
            setState(() {
              _hasError = true;
            });
          }
        })
        ..initialize().then((_) {
          setState(() {
            _isLoading = false;
            _controller.setLooping(true);
            _controller.play();
          });
        }).catchError((error) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
          print('Erreur lors de l\'initialisation de la vidéo : $error');
        });
    } catch (error) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      print('Erreur de mise en cache de la vidéo : $error');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Image.network(
          widget.video.thumbnailUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, progress) {
            return progress == null
                ? child
                : const Center(child: CircularProgressIndicator());
          },
        ),
        if (!_isLoading && !_hasError)
          GestureDetector(
            onTap: () {
              Get.to(() => FullScreenVideo(
                    video: widget.video,
                    user: Get.find<UserController>().user!,
                    videoController: widget.videoController,
                  ));
            },
            child: Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),
          ),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
        if (_hasError)
          const Center(
            child: Text(
              'Erreur de lecture de la vidéo',
              style: TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Positioned(
      right: 10,
      bottom: 50,
      child: Column(
        children: [
          if (widget.userId == widget.video.uid)
            _buildActionButton(
              icon: Icons.delete,
              color: Colors.red,
              label: 'Supprimer',
              onPressed: _showDeleteConfirmation,
            ),
          _buildActionButton(
            icon: Icons.favorite,
            color: widget.video.likes.contains(widget.userId)
                ? Colors.red
                : Colors.white,
            label: '${widget.video.likes.length}',
            onPressed: _toggleLike,
          ),
          const SizedBox(height: 20),
          _buildActionButton(
            icon: Icons.share,
            color: Colors.white,
            label: '${widget.video.shareCount}',
            onPressed: () => _shareVideo(widget.video.videoUrl),
          ),
          const SizedBox(height: 20),
          _buildActionButton(
            icon: Icons.flag,
            color: Colors.white,
            label: '${widget.video.reportCount}',
            onPressed: _reportVideo,
          ),
        ],
      ),
    );
  }

  void _toggleLike() {
    setState(() {
      if (widget.video.likes.contains(widget.userId)) {
        widget.video.likes.remove(widget.userId);
      } else {
        widget.video.likes.add(widget.userId);
      }
    });
    widget.videoController.likeVideo(widget.video.id, widget.userId);
  }

  Future<void> _shareVideo(String videoUrl) async {
    try {
      // Partager via Share Plus
      await Share.share(
        'Découvrez cette vidéo incroyable sur notre application AD.FOOT : $videoUrl',
        subject: 'Vidéo partagée depuis AD.FOOT',
      );

      // Incrémenter le compteur de partage uniquement après un partage réussi
      await widget.videoController.partagerVideo(widget.video.id, videoUrl);
    } catch (e) {
      print('Erreur lors du partage : $e');
      Get.snackbar(
        'Erreur',
        'Impossible de partager la vidéo.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _reportVideo() {
    widget.videoController.signalerVideo(widget.video.id, widget.userId);
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
          icon: Icon(icon, color: color, size: 36),
          onPressed: onPressed,
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmer la suppression'),
          content: const Text('Êtes-vous sûr de vouloir supprimer cette vidéo ?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                widget.videoController.deleteVideo(widget.video.id);
                Navigator.of(context).pop();
                Get.snackbar(
                  'Succès',
                  'Vidéo supprimée avec succès.',
                  backgroundColor: Colors.black.withOpacity(0.8),
                  colorText: Colors.white,
                );
              },
              child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}