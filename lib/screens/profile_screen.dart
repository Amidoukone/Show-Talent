import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/auth_controller.dart';
import 'package:show_talent/controller/profile_controller.dart';
import 'package:show_talent/controller/follow_controller.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/screens/edit_profil_screen.dart';
import 'package:show_talent/screens/chat_screen.dart';
import 'package:show_talent/controller/chat_controller.dart'; // Importer le chat controller

class ProfileScreen extends StatelessWidget {
  final String uid;
  final bool isReadOnly;

  ProfileScreen({super.key, required this.uid, this.isReadOnly = false});

  final ProfileController _profileController = Get.put(ProfileController());
  final FollowController _followController = Get.put(FollowController());
  final ChatController _chatController = Get.put(ChatController()); // Chat Controller pour gérer les conversations

  @override
  Widget build(BuildContext context) {
    _profileController.updateUserId(uid);

    return GetBuilder<ProfileController>(builder: (controller) {
      if (controller.user == null) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      AppUser user = controller.user!;
      bool isFollowing = user.followingsList.contains(AuthController.instance.user?.uid);
      bool isOwnProfile = AuthController.instance.user?.uid == uid;

      return Scaffold(
        appBar: AppBar(
          title: Text(user.nom),
          centerTitle: true,
          backgroundColor: const Color(0xFF214D4F),
          actions: [
            if (!isReadOnly && isOwnProfile)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Get.to(() => EditProfileScreen(user: user));
                },
              ),
            if (!isOwnProfile)
              IconButton(
                icon: const Icon(Icons.message),
                onPressed: () async {
                  // Récupérer ou créer une conversation entre les deux utilisateurs
                  String conversationId = await _chatController.createOrGetConversation(
                    currentUserId: AuthController.instance.user!.uid,
                    otherUserId: user.uid,
                  );
                  
                  // Rediriger vers l'écran de chat avec l'ID de la conversation
                  Get.to(() => ChatScreen(
                        conversationId: conversationId,
                        currentUser: AuthController.instance.user!,
                        otherUserId: user.uid,
                      ));
                },
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: isReadOnly ? null : () {
                      // Logique pour changer la photo de profil (peut-être ouvrir un sélecteur d'image)
                    },
                    child: CircleAvatar(
                      backgroundImage: NetworkImage(user.photoProfil),
                      radius: 50,
                      child: isReadOnly
                          ? null
                          : const Icon(Icons.camera_alt, size: 30, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(user.nom, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text('Followers: ${user.followersList.length}'),
                  Text('Followings: ${user.followingsList.length}'),
                  const SizedBox(height: 10),

                  // Affichage de la biographie si applicable
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Biographie:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(user.bio!),
                  ],
                  const SizedBox(height: 20),
                  
                  ElevatedButton(
                    onPressed: () async {
                      if (isFollowing) {
                        await _followController.unfollowUser(AuthController.instance.user!.uid, user.uid);
                        controller.user!.unfollow(user.uid);
                      } else {
                        await _followController.followUser(AuthController.instance.user!.uid, user.uid);
                        controller.user!.follow(user.uid);
                      }
                      // Mettre à jour l'état
                      isFollowing = !isFollowing;
                      controller.update(); // Met à jour l'interface
                    },
                    child: Text(isFollowing ? 'Se désabonner' : 'Suivre',
                    style: TextStyle(fontSize: 14, color: Colors.white),),
                  ),
                  const SizedBox(height: 20),
                  // Affichage des informations spécifiques au rôle
                  _buildUserRoleInfo(user),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildUserRoleInfo(AppUser user) {
    // Affichage des informations en fonction du rôle
    switch (user.role) {
      case 'joueur':
        return Column(
          children: [
            Text('Position: ${user.position ?? "Non précisée"}'),
            Text('Club actuel: ${user.team ?? "Non précisé"}'), // Utiliser user.team pour le club actuel
            Text('Nombre de matchs: ${user.nombreDeMatchs ?? 0}'),
            Text('Buts: ${user.buts ?? 0}'),
            Text('Assistances: ${user.assistances ?? 0}'),
          ],
        );
      case 'club':
        return Column(
          children: [
            Text('Nom du club: ${user.nomClub ?? "Non précisé"}'),
            Text('Ligue: ${user.ligue ?? "Non précisée"}'),
          ],
        );
      case 'recruteur':
        return Column(
          children: [
            Text('Entreprise: ${user.entreprise ?? "Non précisée"}'),
            Text('Nombre de recrutements: ${user.nombreDeRecrutements ?? 0}'),
          ],
        );
      case 'fan':
        return const Text('Aucune information supplémentaire pour les fans.');
      default:
        return const Text('Rôle inconnu');
    }
  }
}
