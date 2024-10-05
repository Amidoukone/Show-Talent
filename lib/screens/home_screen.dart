import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/controller/video_controller.dart';
import 'package:show_talent/screens/conversation_screen.dart';
import 'package:show_talent/screens/profile_screen.dart'; // Pour afficher le profil de l'utilisateur
import 'package:show_talent/screens/upload_video_screen.dart'; // Écran pour téléverser une vidéo
import 'package:show_talent/screens/video_card.dart';
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
          // Assurez-vous que userController.user est initialisé avant d'accéder à ses valeurs
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
        return ListView.builder(
          itemCount: videoController.videoList.length,
          itemBuilder: (context, index) {
            Video video = videoController.videoList[index];
            return VideoCard(
              video: video,
              user: userController.user!, // Utilisateur connecté
              videoController: videoController, // Passez le contrôleur ici
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
                Get.to(() =>  ConversationsScreen());
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
