import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/screens/profile_screen.dart';
import '../models/video.dart';
import '../models/user.dart';
import 'video_player_item.dart';
import 'package:show_talent/controller/video_controller.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,  // Fond noir pour un effet immersif
      body: Stack(
        children: [
          // Vidéo en plein écran
          Positioned.fill(
            child: VideoPlayerItem(videoUrl: video.videoUrl),
          ),
          // Interactions sur la vidéo
          Positioned(
            bottom: 30,
            right: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildActionButton(Icons.favorite, video.likes.contains(user.uid) ? Colors.red : Colors.white, () {
                  videoController.likeVideo(video.id, user.uid);
                }),
                const SizedBox(height: 10),
                Text('${video.likes.length}', style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 20),
                _buildActionButton(Icons.share, Colors.white, () {
                  videoController.partagerVideo(video.id);
                }),
                const SizedBox(height: 10),
                Text('${video.shareCount}', style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 20),
                _buildActionButton(Icons.flag, Colors.white, () {
                  videoController.signalerVideo(video.id, user.uid);
                }),
                const SizedBox(height: 10),
                Text('${video.reportCount}', style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
          // Nom et description
          Positioned(
            bottom: 30,
            left: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    Get.to(() => ProfileScreen(uid: video.uid, isReadOnly: true));
                  },
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundImage: NetworkImage(video.profilePhoto),
                        radius: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        video.songName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  video.caption,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Méthode pour afficher les boutons d'action (J'aime, Partager, etc.)
  Widget _buildActionButton(IconData icon, Color color, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, color: color, size: 30),
      onPressed: onPressed,
    );
  }
}
