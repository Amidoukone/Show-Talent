import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/controller/video_controller.dart';
import 'package:show_talent/screens/profile_screen.dart'; // Pour afficher le profil de l'utilisateur
import 'package:show_talent/screens/upload_video_screen.dart'; // Écran pour téléverser une vidéo
import 'package:show_talent/screens/full_screen_video.dart'; // Utilisé pour afficher les vidéos en plein écran
import 'package:show_talent/widgets/tiktok_video_player.dart';
import '../models/video.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final VideoController videoController = Get.put(VideoController());
    final UserController userController = Get.find<UserController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AD.FOOT'),
        actions: [
          Obx(() {
            if (userController.user == null) {
              return const CircularProgressIndicator(); // Attendre que l'utilisateur soit chargé
            }
            return IconButton(
              icon: CircleAvatar(
                backgroundImage: NetworkImage(userController.user!.photoProfil ?? ''),
              ),
              onPressed: () {
                Get.to(() => ProfileScreen(uid: userController.user!.uid));
              },
            );
          }),
        ],
      ),
      body: Obx(() {
        if (videoController.videoList.isEmpty) {
          return const Center(child: Text('Aucune vidéo disponible'));
        }
        return PageView.builder(
          scrollDirection: Axis.vertical, // Défilement vertical comme TikTok
          itemCount: videoController.videoList.length,
          itemBuilder: (context, index) {
            Video video = videoController.videoList[index];
            return GestureDetector(
              onTap: () {
                // Afficher la vidéo en plein écran avec les interactions
                Get.to(() => FullScreenVideo(
                  video: video,  // Passez l'objet vidéo
                  user: userController.user!,  // Utilisateur connecté
                  videoController: videoController,  // Contrôleur pour les interactions
                ));
              },
              child: TikTokVideoPlayer(
                videoUrl: video.videoUrl,
                video: video, // Passez l'objet vidéo
                videoController: videoController, // Passez le contrôleur vidéo
                userId: userController.user!.uid,  // ID de l'utilisateur connecté
              ),
            );
          },
        );
      }),

      // Condition pour afficher le FloatingActionButton pour les joueurs seulement
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,  // Déplacer le bouton à gauche
      floatingActionButton: Obx(() {
        // Vérification si l'utilisateur est un joueur avant d'afficher le bouton
        if (userController.user?.role == 'joueur') {
          return FloatingActionButton(
            backgroundColor: const Color(0xFF214D4F),
            heroTag: 'addVideo',
            onPressed: () {
              // Ouvrir l'écran pour téléverser une vidéo
              Get.to(() => const UploadVideoScreen());
            },
            child: const Icon(Icons.add), // Icône pour ajouter une vidéo
          );
        } else {
          // Ne rien afficher si l'utilisateur n'est pas un joueur
          return const SizedBox.shrink();
        }
      }),
    );
  }
}
