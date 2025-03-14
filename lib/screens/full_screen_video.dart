import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/widgets/video_manager.dart';
import '../models/video.dart';
import '../models/user.dart';

class FullScreenVideo extends StatelessWidget {
  final Video video;
  final AppUser user;
  final dynamic videoController; // Utilisé dans SmartVideoPlayer en interne

  const FullScreenVideo({
    super.key,
    required this.video,
    required this.user,
    required this.videoController,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SmartVideoPlayer(
            videoUrl: video.videoUrl,
            video: video,
          ),
          _buildVideoInfo(context),
        ],
      ),
    );
  }

  Widget _buildVideoInfo(BuildContext context) {
    return Positioned(
      bottom: 40,
      left: 10,
      right: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () async {
              // Pause la vidéo avant navigation
              VideoManager().pause(video.videoUrl);

              // Navigue vers le profil
              if (video.uid.isNotEmpty) {
                await Get.to(() => ProfileScreen(uid: video.uid, isReadOnly: true));
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
                        : 'https://via.placeholder.com/150',
                  ),
                  radius: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    video.songName.isNotEmpty
                        ? video.songName
                        : 'Musique inconnue',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            video.caption.isNotEmpty ? video.caption : 'Pas de légende',
            style: const TextStyle(color: Colors.white, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
