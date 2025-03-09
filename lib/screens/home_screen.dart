import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/screens/upload_video_screen.dart';
import 'package:adfoot/screens/full_screen_video.dart';
import 'package:adfoot/widgets/tiktok_video_player.dart';
import '../models/video.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final VideoController videoController = Get.put(VideoController());
    final UserController userController = Get.find<UserController>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'AD.FOOT',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
actions: [
  Obx(() {
    final user = userController.user;
    if (user == null) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: CircularProgressIndicator(),
      );
    }
    return IconButton(
      icon: CircleAvatar(
        backgroundImage: NetworkImage(user.photoProfil.isNotEmpty
            ? user.photoProfil
            : 'https://via.placeholder.com/150'),
      ),
      onPressed: () {
        Get.to(() => ProfileScreen(uid: user.uid));
      },
    );
  }),
],

      ),
      body: Obx(() {
        if (videoController.videoList.isEmpty) {
          return const Center(
            child: Text(
              'Aucune vidéo disponible',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          );
        }

        // PageView pour afficher les vidéos
        return PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: videoController.videoList.length,
          itemBuilder: (context, index) {
            Video video = videoController.videoList[index];

            // Vidéo avec redirection vers FullScreenVideo
            return InkWell(
              onTap: () {
                Get.to(() => FullScreenVideo(
                      video: video,
                      user: userController.user!,
                      videoController: videoController,
                    ));
              },
              child: TikTokVideoPlayer(
                videoUrl: video.videoUrl,
                video: video,
                videoController: videoController,
                userId: userController.user!.uid,
                enableTapToPlayPause:
                    false, // Désactiver la lecture/pause sur clic
              ),
            );
          },
        );
      }),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: Obx(() {
        // Bouton flottant visible uniquement pour les joueurs
        if (userController.user?.role == 'joueur') {
          return FloatingActionButton(
            backgroundColor: const Color(0xFF214D4F),
            foregroundColor: Colors.white,
            heroTag: 'addVideo',
            onPressed: () {
              Get.to(() => const UploadVideoScreen());
            },
            child: const Icon(Icons.add),
          );
        } else {
          return const SizedBox.shrink();
        }
      }),
    );
  }
}
