import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/profile_controller.dart';
import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/screens/chat_screen.dart';
import 'package:adfoot/screens/edit_profil_screen.dart';
import 'package:adfoot/screens/follow_list_screen.dart';
import 'package:adfoot/screens/video_player_screen.dart';

class ProfileScreen extends StatelessWidget {
  final String uid;
  final bool isReadOnly;

  ProfileScreen({super.key, required this.uid, this.isReadOnly = false});

  final ProfileController _profileController = Get.put(ProfileController());
  final AuthController _authController = Get.put(AuthController());
  final FollowController _followController = Get.put(FollowController());
  final ChatController _chatController = Get.put(ChatController());
  final ImagePicker _imagePicker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    // Mise à jour des informations utilisateur dans le ProfileController
    _profileController.updateUserId(uid);

    return GetBuilder<ProfileController>(builder: (controller) {
      if (controller.user == null) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      AppUser user = controller.user!;
      bool isOwnProfile = _authController.user?.uid == uid;

      return Scaffold(
        appBar: AppBar(
          title: Text(
            user.nom.isNotEmpty ? user.nom : 'Nom inconnu',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
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
                  await _handleSendMessage(user);
                },
              ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildProfilePhotoSection(user, isOwnProfile),
                const SizedBox(height: 20),
                _buildStatSection(user),
                if (!isOwnProfile) _buildFollowUnfollowButton(user),
                const SizedBox(height: 20),
                _buildBioSection(user),
                const SizedBox(height: 20),
                _buildSpecificInfoSection(user),
                const SizedBox(height: 20),
                if (user.role == 'joueur') _buildVideosSection(user),
              ],
            ),
          ),
        ),
      );
    });
  }

  /// Gestion de l'envoi de message
  Future<void> _handleSendMessage(AppUser user) async {
    final currentUser = _authController.user;

    if (currentUser == null || currentUser.uid.isEmpty) {
      Get.snackbar(
        'Erreur',
        'Vous devez être connecté pour envoyer un message.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    try {
      String conversationId = await _chatController.createOrGetConversation(
        currentUserId: currentUser.uid,
        otherUserId: user.uid,
      );

      if (conversationId.isNotEmpty) {
        Get.to(() => ChatScreen(
              conversationId: conversationId,
              otherUser: user,
            ));
      } else {
        throw Exception('Conversation ID invalide.');
      }
    } catch (e) {
      Get.snackbar(
        'Erreur',
        'Une erreur s\'est produite lors de l\'envoi du message : $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// Section de la photo de profil
  Widget _buildProfilePhotoSection(AppUser user, bool isOwnProfile) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Obx(() => CircleAvatar(
              radius: 60,
              backgroundImage: _profileController.isLoadingPhoto.value
                  ? null
                  : NetworkImage(user.photoProfil.isNotEmpty
                      ? user.photoProfil
                      : 'https://via.placeholder.com/150'),
              child: _profileController.isLoadingPhoto.value
                  ? const CircularProgressIndicator()
                  : null,
            )),
        if (isOwnProfile && !isReadOnly)
          Positioned(
            bottom: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              onPressed: () => _changeProfilePhoto(user.uid),
            ),
          ),
      ],
    );
  }

  /// Section des statistiques
  Widget _buildStatSection(AppUser user) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => Get.to(
              () => FollowListScreen(uid: user.uid, listType: 'followers')),
          child: _buildStatItem('Followers', user.followersList.length),
        ),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: () => Get.to(
              () => FollowListScreen(uid: user.uid, listType: 'followings')),
          child: _buildStatItem('Followings', user.followingsList.length),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, int value) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(label),
      ],
    );
  }

  /// Bouton Suivre/Dessuivre
  Widget _buildFollowUnfollowButton(AppUser user) {
    final String? currentUserId = _authController.user?.uid;

    if (currentUserId == null) {
      return const SizedBox.shrink();
    }

    bool isFollowing = user.followersList.contains(currentUserId);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ElevatedButton(
        onPressed: () async {
          try {
            if (isFollowing) {
              await _followController.unfollowUser(currentUserId, user.uid);
              user.followersList.remove(currentUserId);
            } else {
              await _followController.followUser(currentUserId, user.uid);
              user.followersList.add(currentUserId);
            }
            _profileController
                .update(); // Met à jour les informations utilisateur localement
          } catch (e) {
            Get.snackbar(
              'Erreur',
              'Une erreur s\'est produite lors de l\'opération : $e',
              backgroundColor: Colors.red,
              colorText: Colors.white,
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isFollowing ? Colors.redAccent : Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
          isFollowing ? 'Dessuivre' : 'Suivre',
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
    );
  }

  /// Changer la photo de profil
  Future<void> _changeProfilePhoto(String userId) async {
    final XFile? pickedImage =
        await _imagePicker.pickImage(source: ImageSource.gallery);
    if (pickedImage != null) {
      await _profileController.updateProfilePhoto(userId, pickedImage.path);
    }
  }

  /// Section de la biographie
  Widget _buildBioSection(AppUser user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Biographie',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            user.bio?.isNotEmpty == true
                ? user.bio!
                : 'Aucune biographie disponible.',
            style: const TextStyle(fontSize: 16, color: Colors.black87),
            textAlign: TextAlign.left,
          ),
        ],
      ),
    );
  }

  /// Informations spécifiques selon le rôle
  Widget _buildSpecificInfoSection(AppUser user) {
    switch (user.role) {
      case 'joueur':
        return Column(
          children: [
            _infoTile('Position', user.position),
            _infoTile('Club actuel', user.team),
            _infoTile('Nombre de matchs', user.nombreDeMatchs?.toString()),
            _infoTile('Buts', user.buts?.toString()),
            _infoTile('Assistances', user.assistances?.toString()),
          ],
        );
      case 'club':
        return Column(
          children: [
            _infoTile('Nom du club', user.nomClub),
            _infoTile('Ligue', user.ligue),
          ],
        );
      case 'recruteur':
        return Column(
          children: [
            _infoTile('Entreprise', user.entreprise),
            _infoTile('Nombre de recrutements',
                user.nombreDeRecrutements?.toString()),
          ],
        );
      case 'fan':
      default:
        return const Text("Aucune information spécifique pour ce rôle.");
    }
  }

  Widget _infoTile(String label, String? value) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value?.isNotEmpty == true ? value! : 'Non spécifié'),
    );
  }

  /// Section des vidéos
  Widget _buildVideosSection(AppUser user) {
    return Obx(() {
      List<Video> userVideos = _profileController.videoList;

      if (userVideos.isEmpty) {
        return const Text("Aucune vidéo publiée.");
      }

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
              Get.to(() =>
                  VideoPlayerScreen(videoUrl: video.videoUrl, video: video));
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                video.thumbnail,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.error),
              ),
            ),
          );
        },
      );
    });
  }
}
