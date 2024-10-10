import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/video_controller.dart';
import 'package:show_talent/models/video.dart';

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
    required this.userId,
  });

  @override
  _TikTokVideoPlayerState createState() => _TikTokVideoPlayerState();
}

class _TikTokVideoPlayerState extends State<TikTokVideoPlayer> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    // Initialisation du contrôleur vidéo avec l'URL de la vidéo
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() {}); // Rebuild pour initialiser la vidéo
        _controller.play(); // Lecture automatique
        _controller.setLooping(true); // Boucle infinie
      });
  }

  @override
  void dispose() {
    _controller.dispose(); // Libérer les ressources
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Fond noir pour s'assurer que les espaces vides sont noirs
        Container(
          color: Colors.black,  // Fond noir pour les bandes noires
          child: _controller.value.isInitialized
              ? Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,  // Respecter le ratio d'origine de la vidéo
                    child: VideoPlayer(_controller),
                  ),
                )
              : const Center(
                  child: CircularProgressIndicator(),  // Indicateur de chargement
                ),
        ),
        // Interactions sur la vidéo (likes, partage, etc.)
        Positioned(
          right: 10,
          bottom: 50,
          child: Column(
            children: [
              if (widget.userId == widget.video.uid)
                _buildActionButton(
                  icon: Icons.delete,
                  color: Colors.red,
                  label: 'Supprimer',
                  onPressed: () {
                    _showDeleteConfirmation();
                  },
                ),
              _buildActionButton(
                icon: Icons.favorite,
                color: widget.video.likes.contains(widget.userId) ? Colors.red : Colors.white,
                label: '${widget.video.likes.length}',
                onPressed: () {
                  widget.videoController.likeVideo(widget.video.id, widget.userId);
                },
              ),
              const SizedBox(height: 20),
              _buildActionButton(
                icon: Icons.share,
                color: Colors.white,
                label: '${widget.video.shareCount}',
                onPressed: () {
                  widget.videoController.partagerVideo(widget.video.id);
                },
              ),
              const SizedBox(height: 20),
              _buildActionButton(
                icon: Icons.flag,
                color: Colors.white,
                label: '${widget.video.reportCount}',
                onPressed: () {
                  widget.videoController.signalerVideo(widget.video.id, widget.userId);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Méthode pour construire les boutons d'action (J'aime, Partager, etc.)
  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        IconButton(
          icon: Icon(icon, color: color, size: 30),
          onPressed: onPressed,
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }

  // Confirmation de suppression de la vidéo
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
                Navigator.of(context).pop(); // Fermer la boîte de dialogue
              },
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                widget.videoController.deleteVideo(widget.video.id);
                Navigator.of(context).pop();
                Get.snackbar('Succès', 'Vidéo supprimée avec succès.');
              },
              child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}
