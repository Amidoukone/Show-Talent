import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/video_controller.dart';
import 'package:show_talent/screens/profile_screen.dart'; // Pour voir le profil du propriétaire de la vidéo
import '../models/video.dart';
import '../models/user.dart';
import 'video_player_item.dart';

class VideoCard extends StatelessWidget {
  final Video video;
  final AppUser user; // L'utilisateur connecté
  final VideoController videoController;

  const VideoCard({
    super.key,
    required this.video,
    required this.user,
    required this.videoController,
  });

  @override
  Widget build(BuildContext context) {
    // Obtenir la taille de l'écran de l'utilisateur
    final screenWidth = MediaQuery.of(context).size.width;

    return Card(
      elevation: 4, // Ajoute une légère ombre pour un design moderne
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15), // Bords arrondis pour un effet moderne
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vidéo qui occupe toute la largeur de la carte
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(15),
              topRight: Radius.circular(15),
            ), // Arrondir le haut de la vidéo pour correspondre à la carte
            child: Container(
              width: screenWidth, // Utiliser toute la largeur de l'écran
              color: Colors.black, // Fond noir pendant le chargement
              child: FittedBox(
                fit: BoxFit.cover, // Permet à la vidéo de couvrir tout l'espace sans étirer
                child: SizedBox(
                  width: screenWidth, // S'assure que la vidéo occupe bien la largeur disponible
                  height: screenWidth * (9 / 16), // Ratio 16:9 pour les vidéos
                  child: VideoPlayerItem(videoUrl: video.videoUrl),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Affichage du profil de celui qui a posté la vidéo
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        // Redirection vers le profil du propriétaire de la vidéo en mode lecture seule
                        Get.to(() => ProfileScreen(uid: video.uid, isReadOnly: true));
                      },
                      child: CircleAvatar(
                        backgroundImage: NetworkImage(video.profilePhoto),
                        radius: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        video.songName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis, // Gérer les textes trop longs
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Légende de la vidéo
                Text(
                  video.caption,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis, // Limiter à deux lignes pour éviter l'overflow
                ),
                const SizedBox(height: 8),
                // Boutons d'interaction (J'aime, Partager, Signaler)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Bouton "J'aime"
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            video.likes.contains(user.uid)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: Colors.red,
                          ),
                          onPressed: () {
                            videoController.likeVideo(video.id, user.uid);
                          },
                        ),
                        Text('${video.likes.length} likes'),
                      ],
                    ),

                    // Bouton "Partager"
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.share),
                          onPressed: () {
                            videoController.partagerVideo(video.id);
                          },
                        ),
                        Text('${video.shareCount} partages'),
                      ],
                    ),

                    // Bouton "Signaler"
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.flag),
                          onPressed: () {
                            videoController.signalerVideo(video.id, user.uid);
                          },
                        ),
                        Text('${video.reportCount} signaler'),
                      ],
                    ),
                  ],
                ),

                // Bouton "Supprimer" (Visible uniquement pour le propriétaire de la vidéo)
                if (user.uid == video.uid)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text(
                        'Supprimer',
                        style: TextStyle(color: Colors.red),
                      ),
                      onPressed: () {
                        _showDeleteConfirmation(context, video);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Méthode pour afficher une boîte de dialogue de confirmation avant la suppression
  void _showDeleteConfirmation(BuildContext context, Video video) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmer la suppression'),
          content: const Text('Êtes-vous sûr de vouloir supprimer cette vidéo ?'),
          actions: [
            TextButton(
              onPressed: () {
                Get.back(); // Fermer la boîte de dialogue
              },
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () async {
                // Supprimer la vidéo et mettre à jour l'affichage
                await videoController.deleteVideo(video.id);
                Get.back(); // Fermer la boîte de dialogue après la suppression
              },
              child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}
