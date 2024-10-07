import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/video_controller.dart';
import 'package:show_talent/models/video.dart';

class TikTokVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final Video video; // Ajout de la vidéo pour la suppression
  final VideoController videoController; // Contrôleur pour les actions sur la vidéo
  final String userId; // ID de l'utilisateur connecté

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
    // Utilisation de `VideoPlayerController.networkUrl`
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() {}); // Rebuild pour initialiser la vidéo
        _controller.play(); // Lecture automatique
        _controller.setLooping(true); // Boucler la vidéo
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
        // Lecture de la vidéo en plein écran
        _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const Center(
                child: CircularProgressIndicator(),
              ),
        // Interactions sur la vidéo (supprimer, liker, partager, signaler)
        Positioned(
          right: 10,
          bottom: 50,
          child: Column(
            children: [
              // Bouton supprimer (visible uniquement pour le propriétaire)
              if (widget.userId == widget.video.uid)
                _buildActionButton(
                  icon: Icons.delete,
                  color: Colors.red,
                  label: 'Supprimer',
                  onPressed: () {
                    _showDeleteConfirmation(); // Afficher la confirmation de suppression
                  },
                ),
              // Autres interactions (liker, partager, signaler)
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

  // Méthode pour construire les boutons d'action (icône + label)
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

  // Méthode pour afficher la boîte de dialogue de confirmation avant suppression
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
                widget.videoController.deleteVideo(widget.video.id); // Supprimer la vidéo
                Navigator.of(context).pop(); // Fermer après suppression
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
