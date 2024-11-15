import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/auth_controller.dart';
import 'package:show_talent/controller/profile_controller.dart';
import 'package:show_talent/controller/follow_controller.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/screens/edit_profil_screen.dart';
import 'package:show_talent/screens/chat_screen.dart';
import 'package:show_talent/controller/chat_controller.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatelessWidget {
  final String uid;
  final bool isReadOnly;

  ProfileScreen({super.key, required this.uid, this.isReadOnly = false});

  final ProfileController _profileController = Get.put(ProfileController());
  final FollowController _followController = Get.put(FollowController());
  final ChatController _chatController = Get.put(ChatController());

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
      bool isOwnProfile = AuthController.instance.user?.uid == uid;
      bool isFollowing = user.followersList.contains(AuthController.instance.user?.uid);

      return Scaffold(
        appBar: AppBar(
          title: Text(user.nom, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          centerTitle: true,
          backgroundColor: const Color(0xFF214D4F),
          actions: [
            if (!isReadOnly && isOwnProfile)
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white),
                onPressed: () {
                  Get.to(() => EditProfileScreen(user: user));
                },
              ),
            if (!isOwnProfile)
              IconButton(
                icon: const Icon(Icons.message, color: Colors.white),
                onPressed: () async {
                  String conversationId = await _chatController.createOrGetConversation(
                    currentUserId: AuthController.instance.user!.uid,
                    otherUserId: user.uid,
                  );
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
                  // Photo de profil stylisée
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return const LinearGradient(
                            colors: [Colors.blueAccent, Colors.greenAccent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds);
                        },
                        child: CircleAvatar(
                          radius: 68,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      GestureDetector(
                        onTap: isReadOnly ? null : () async {
                          await _showProfilePhotoOptions(context, user);
                        },
                        child: Obx(() => CircleAvatar(
                          radius: 60,
                          backgroundImage: controller.isLoadingPhoto.value
                              ? null
                              : NetworkImage(user.photoProfil),
                          child: controller.isLoadingPhoto.value
                              ? const CircularProgressIndicator(color: Colors.white)
                              : isReadOnly
                                  ? null
                                  : const Icon(Icons.camera_alt, size: 30, color: Colors.white),
                        )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Texte pour voir la photo de profil en grand
                  GestureDetector(
                    onTap: () {
                      _showFullProfilePhoto(context, user.photoProfil);
                    },
                    child: const Text(
                      'Voir photo de profil',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Nom de l'utilisateur
                  Text(user.nom, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),

                  const SizedBox(height: 10),

                  // Section des followers et followings
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatItem('Followers', user.followersList.length),
                      const SizedBox(width: 20),
                      _buildStatItem('Followings', user.followingsList.length),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Biographie de l'utilisateur
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        user.bio!,
                        style: const TextStyle(fontSize: 16, color: Colors.black87),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Bouton Suivre/Se désabonner
                  if (!isOwnProfile)
                    ElevatedButton(
                      onPressed: () async {
                        if (isFollowing) {
                          await _followController.unfollowUser(AuthController.instance.user!.uid, user.uid);
                          controller.user!.unfollow(user.uid);
                        } else {
                          await _followController.followUser(AuthController.instance.user!.uid, user.uid);
                          controller.user!.follow(user.uid);
                        }
                        isFollowing = !isFollowing;
                        controller.update();
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                        backgroundColor: isFollowing ? Colors.red : const Color(0xFF214D4F),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: Text(
                        isFollowing ? 'Se désabonner' : 'Suivre',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Informations selon le rôle de l'utilisateur
                  _buildUserRoleInfo(user),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  // Méthode pour afficher une statistique
  Widget _buildStatItem(String label, int value) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey),
        ),
      ],
    );
  }

  // Méthode pour afficher les options de changement de photo de profil
  Future<void> _showProfilePhotoOptions(BuildContext context, AppUser user) async {
    final ImagePicker picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.camera),
            title: const Text('Prendre une photo'),
            onTap: () async {
              Navigator.pop(context);
              final XFile? photo = await picker.pickImage(source: ImageSource.camera);
              if (photo != null) {
                await _profileController.updateProfilePhoto(user.uid, photo.path);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choisir depuis la galerie'),
            onTap: () async {
              Navigator.pop(context);
              final XFile? photo = await picker.pickImage(source: ImageSource.gallery);
              if (photo != null) {
                await _profileController.updateProfilePhoto(user.uid, photo.path);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Supprimer la photo de profil'),
            onTap: () async {
              Navigator.pop(context);
              await _profileController.updateProfilePhoto(user.uid, '');
            },
          ),
        ],
      ),
    );
  }

  // Méthode pour afficher la photo de profil en grand
  void _showFullProfilePhoto(BuildContext context, String photoUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10.0),
              child: Image.network(
                photoUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Méthode pour afficher les informations en fonction du rôle de l'utilisateur
  Widget _buildUserRoleInfo(AppUser user) {
    switch (user.role) {
      case 'joueur':
        return Column(
          children: [
            Text('Position: ${user.position ?? "Non précisée"}'),
            Text('Club actuel: ${user.team ?? "Non précisé"}'),
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
