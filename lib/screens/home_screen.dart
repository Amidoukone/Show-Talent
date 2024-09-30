import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/controller/video_controller.dart';
import 'package:show_talent/screens/login_screen.dart';
import '../models/user.dart';
import '../models/video.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final VideoController videoController = Get.put(VideoController());
    final UserController userController = Get.find<UserController>(); // S'assurer que le UserController est trouvé

    if (userController.user == null) {
      return const Center(child: CircularProgressIndicator()); // Afficher un loader si l'utilisateur est encore en chargement
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Bienvenue ${userController.user!.nom}'), // Accès au nom de l'utilisateur
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              userController.signOut(); // Déconnexion de l'utilisateur
              Get.offAll(() => const LoginScreen()); // Redirection vers la page de connexion
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _buildHomeContent(userController.user!), // Afficher le contenu en fonction du rôle
            ),
          ),
          Expanded(
            child: Obx(
              () {
                if (videoController.videoList.isEmpty) {
                  return const Center(
                    child: Text('Aucune vidéo disponible'),
                  );
                }

                return ListView.builder(
                  itemCount: videoController.videoList.length,
                  itemBuilder: (context, index) {
                    Video video = videoController.videoList[index];
                    return VideoCard(video: video, user: userController.user!);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Méthode qui affiche un contenu différent selon le rôle de l'utilisateur
  Widget _buildHomeContent(AppUser user) {
    switch (user.role) {
      case 'joueur':
        return const Text('Contenu pour les joueurs');
      case 'club':
        return const Text('Contenu pour les clubs');
      case 'recruteur':
        return const Text('Contenu pour les recruteurs');
      case 'fan':
        return const Text('Contenu pour les fans');
      case 'coach':
        return const Text('Contenu pour les coachs');
      default:
        return const Text('Rôle inconnu');
    }
  }
}

class VideoCard extends StatelessWidget {
  final Video video;
  final AppUser user;

  const VideoCard({super.key, required this.video, required this.user});

  @override
  Widget build(BuildContext context) {
    final VideoController videoController = Get.find<VideoController>();

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.network(
            video.thumbnail,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(video.songName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(video.caption, style: const TextStyle(fontSize: 14)),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        video.likes.contains(user.uid) ? Icons.favorite : Icons.favorite_border,
                        color: Colors.red,
                      ),
                      onPressed: () {
                        videoController.likeVideo(video.id, user.uid);
                      },
                    ),
                    Text('${video.likes.length} likes'),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: () {
                        // Logique de partage à implémenter
                      },
                    ),
                    Text('${video.shareCount} partages'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
