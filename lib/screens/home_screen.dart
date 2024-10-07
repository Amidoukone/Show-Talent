import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/controller/video_controller.dart';
import 'package:show_talent/screens/conversation_screen.dart';
import 'package:show_talent/screens/profile_screen.dart'; // Pour afficher le profil de l'utilisateur
import 'package:show_talent/screens/upload_video_screen.dart'; // Écran pour téléverser une vidéo
import 'package:show_talent/screens/full_screen_video.dart'; // Pour afficher les vidéos en plein écran
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
                // Lorsqu'une vidéo est sélectionnée, elle est affichée en plein écran
                Get.to(() => FullScreenVideo(
                  video: video,
                  user: userController.user!,  // Utilisateur connecté
                  videoController: videoController,
                ));
              },
              child: TikTokVideoPlayer(videoUrl: video.videoUrl),  // Utiliser le lecteur vidéo
            );
          },
        );
      }),

      // Deux FloatingActionButtons: un à gauche (conversation) et un à droite (ajouter vidéo)
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,  // Place le bouton central
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // FloatingActionButton pour les conversations (à gauche)
          Padding(
            padding: const EdgeInsets.only(left: 30.0),  // Laisser de la place à gauche
            child: FloatingActionButton(
              backgroundColor: const Color(0xFF214D4F),
              heroTag: 'conversation',
              onPressed: () {
                // Ouvrir l'écran des conversations
                Get.to(() => ConversationsScreen());
              },
              child: const Icon(Icons.chat), // Icône pour les conversations
            ),
          ),
          // FloatingActionButton pour l'ajout de vidéo (à droite)
          Padding(
            padding: const EdgeInsets.only(right: 30.0),  // Laisser de la place à droite
            child: FloatingActionButton(
              backgroundColor: const Color(0xFF214D4F),
              heroTag: 'addVideo',
              onPressed: () {
                // Ouvrir l'écran pour téléverser une vidéo
                Get.to(() => const UploadVideoScreen());
              },
              child: const Icon(Icons.add), // Icône pour ajouter une vidéo
            ),
          ),
        ],
      ),
    );
  }
}
