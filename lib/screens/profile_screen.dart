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
          title: Text(user.nom, style: const TextStyle(fontSize: 22)),
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
                  GestureDetector(
                    onTap: isReadOnly ? null : () async {
                      await _showProfilePhotoOptions(context, user);
                    },
                    child: CircleAvatar(
                      backgroundImage: NetworkImage(user.photoProfil),
                      radius: 60,
                      child: isReadOnly
                          ? null
                          : const Icon(Icons.camera_alt, size: 30, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Texte 'Voir photo de profil'
                  GestureDetector(
                    onTap: () {
                      _showFullProfilePhoto(context, user.photoProfil);
                    },
                    child: const Text(
                      'Voir photo de profil',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 16,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(user.nom, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text('Followers: ${user.followersList.length}', style: const TextStyle(fontSize: 16)),
                  Text('Followings: ${user.followingsList.length}', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 20),
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    const Text('Biographie:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text(user.bio!, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 10),
                  ],
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
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
                        backgroundColor: isFollowing ? Colors.red : const Color(0xFF214D4F),
                      ),
                      child: Text(
                        isFollowing ? 'Se désabonner' : 'Suivre',
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _buildUserRoleInfo(user),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  // Affiche la photo de profil en grand
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
