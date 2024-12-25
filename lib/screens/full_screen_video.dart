import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/screens/profile_screen.dart';
import '../models/video.dart';
import '../models/user.dart';
import 'video_player_item.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class FullScreenVideo extends StatelessWidget {
  final Video video;
  final AppUser user;
  final VideoController videoController;

  const FullScreenVideo({
    super.key,
    required this.video,
    required this.user,
    required this.videoController,
  });

  Future<File> _cacheVideo(String videoUrl) async {
    try {
      return await DefaultCacheManager().getSingleFile(videoUrl);
    } catch (e) {
      throw Exception('Erreur lors du cache de la vidéo : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<File>(
        future: _cacheVideo(video.videoUrl),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Erreur lors du chargement de la vidéo',
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
            );
          }

          return Stack(
            children: [
              // Lecteur vidéo en plein écran
              Positioned.fill(
                child: VideoPlayerItem(videoUrl: video.videoUrl),
              ),

              // Actions de la vidéo
              Positioned(
                right: 10,
                bottom: 80,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildActionButton(
                      icon: Icons.favorite,
                      color: video.likes.contains(user.uid)
                          ? Colors.red
                          : Colors.white,
                      label: '${video.likes.length}',
                      onPressed: () {
                        videoController.likeVideo(video.id, user.uid);
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildActionButton(
                      icon: Icons.share,
                      color: Colors.white,
                      label: '${video.shareCount}',
                      onPressed: () {
                        videoController.partagerVideo(video.id);
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildActionButton(
                      icon: Icons.flag,
                      color: Colors.white,
                      label: '${video.reportCount}',
                      onPressed: () {
                        videoController.signalerVideo(video.id, user.uid);
                      },
                    ),
                  ],
                ),
              ),

              // Informations sur l'utilisateur
              Positioned(
                bottom: 80,
                left: 10,
                child: GestureDetector(
                  onTap: () {
                    if (video.uid.isNotEmpty) {
                      Get.to(() =>
                          ProfileScreen(uid: video.uid, isReadOnly: true));
                    } else {
                      Get.snackbar(
                        'Erreur',
                        'Utilisateur introuvable.',
                        backgroundColor: Colors.redAccent,
                        colorText: Colors.white,
                      );
                    }
                  },
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundImage: NetworkImage(
                            video.profilePhoto.isNotEmpty
                                ? video.profilePhoto
                                : 'https://via.placeholder.com/150'),
                        radius: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        video.songName.isNotEmpty
                            ? video.songName
                            : 'Musique inconnue',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

              // Légende de la vidéo
              Positioned(
                bottom: 40,
                left: 10,
                child: Text(
                  video.caption.isNotEmpty ? video.caption : 'Pas de légende',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Widget générique pour les boutons d'action
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
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}
