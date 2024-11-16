import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/auth_controller.dart';
import 'package:show_talent/controller/profile_controller.dart';
import 'package:show_talent/controller/video_controller.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/models/video.dart';
import 'package:show_talent/screens/edit_profil_screen.dart';
import 'package:show_talent/screens/chat_screen.dart';
import 'package:show_talent/screens/video_player_screen.dart';
import 'package:show_talent/controller/chat_controller.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatelessWidget {
  final String uid;
  final bool isReadOnly;

  ProfileScreen({super.key, required this.uid, this.isReadOnly = false});

  final ProfileController _profileController = Get.put(ProfileController());
  final ChatController _chatController = Get.put(ChatController());
  final VideoController _videoController = Get.put(VideoController());

  @override
  Widget build(BuildContext context) {
    _profileController.updateUserId(uid);
    _videoController.fetchVideos(); // Charger les vidéos.

    return GetBuilder<ProfileController>(builder: (controller) {
      if (controller.user == null) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      AppUser user = controller.user!;
      bool isOwnProfile = AuthController.instance.user?.uid == uid;

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
                  // Section Photo de Profil
                  _buildProfilePhotoSection(user, isReadOnly),

                  const SizedBox(height: 20),

                  // Section des stats Followers / Followings
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
                  if (user.bio != null && user.bio!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        user.bio!,
                        style: const TextStyle(fontSize: 16, color: Colors.black87),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Informations spécifiques au rôle
                  _buildUserRoleInfo(user),

                  // Section Vidéos affichée uniquement pour les joueurs
                  if (user.role == 'joueur') ...[
                    const SizedBox(height: 20),
                    _buildVideosSection(user),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  // Méthode pour afficher la photo de profil stylisée
  Widget _buildProfilePhotoSection(AppUser user, bool isReadOnly) {
    return Stack(
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
            await _showProfilePhotoOptions(Get.context!, user);
          },
          child: Obx(() => CircleAvatar(
                radius: 60,
                backgroundImage: _profileController.isLoadingPhoto.value
                    ? null
                    : NetworkImage(user.photoProfil),
                child: _profileController.isLoadingPhoto.value
                    ? const CircularProgressIndicator(color: Colors.white)
                    : isReadOnly
                        ? null
                        : const Icon(Icons.camera_alt, size: 30, color: Colors.white),
              )),
        ),
      ],
    );
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

  // Méthode pour afficher les vidéos du joueur
  Widget _buildVideosSection(AppUser user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vidéos publiées',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Obx(() {
          // Filtrer les vidéos par UID
          List<Video> userVideos = _videoController.videoList
              .where((video) => video.uid == user.uid)
              .toList();

          if (userVideos.isEmpty) {
            return const Text('Aucune vidéo publiée.', style: TextStyle(fontSize: 16));
          }

          // Affichage des miniatures des vidéos
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: userVideos.length,
            itemBuilder: (context, index) {
              Video video = userVideos[index];
              return GestureDetector(
                onTap: () {
                  // Naviguer vers un lecteur vidéo
                  Get.to(() => VideoPlayerScreen(videoUrl: video.videoUrl, video: video));
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    video.thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }

  // Méthode pour afficher les informations spécifiques à l'utilisateur
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
        ],
      ),
    );
  }
}
