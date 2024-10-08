import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:show_talent/controller/auth_controller.dart';
import 'package:show_talent/controller/profile_controller.dart';
import 'package:show_talent/controller/chat_controller.dart'; // Importer le ChatController
import 'package:show_talent/screens/chat_screen.dart'; // Importer l'écran de chat
import 'package:show_talent/screens/edit_profil_screen.dart';
import '../models/user.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProfileScreen extends StatelessWidget {
  final String uid;
  final bool isReadOnly;
  ProfileScreen({super.key, required this.uid, this.isReadOnly = false});

  final ProfileController _profileController = Get.put(ProfileController());
  final ChatController _chatController = Get.put(ChatController()); // Ajouter le ChatController
  final ImagePicker _picker = ImagePicker();

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

      return Scaffold(
        appBar: AppBar(
          title: Text(user.nom),
          centerTitle: true,
          backgroundColor: const Color(0xFF214D4F),
          actions: [
            // Si c'est le profil de l'utilisateur connecté et qu'il peut le modifier
            if (!isReadOnly && AuthController.instance.user?.uid == user.uid)
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  _showProfileOptions(context, user);
                },
              )
            // Si c'est un autre utilisateur, montrer l'icône de message pour l'envoyer un message
            else if (isReadOnly && AuthController.instance.user?.uid != user.uid)
              IconButton(
                icon: const Icon(Icons.message),
                onPressed: () async {
                  String conversationId = await _chatController.createConversation(user);
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
                  // Photo de profil
                  GestureDetector(
                    onTap: isReadOnly
                        ? null
                        : () {
                            _changeProfilePhoto(user.uid);
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
                  // Nom de l'utilisateur
                  Text(
                    user.nom,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  
                  if (user.role != 'fan') ...[
                    Text('Followers: ${user.followers}'),
                    Text('Followings: ${user.followings}'),
                    const SizedBox(height: 10),
                  ],
                  _buildUserRoleInfo(user),
                  const SizedBox(height: 20),

                  // Si l'utilisateur est un joueur avec des vidéos publiées, les afficher
                  if (user.role == 'joueur' && user.videosPubliees != null && user.videosPubliees!.isNotEmpty)
                    _buildVideosGrid(user.videosPubliees!)
                  else if (user.role == 'joueur')
                    const Text('Pas de vidéos publiées.'),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Future<void> _changeProfilePhoto(String uid) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      File imageFile = File(pickedFile.path);
      String fileName = 'profile_pics/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
      UploadTask uploadTask = FirebaseStorage.instance.ref().child(fileName).putFile(imageFile);

      try {
        TaskSnapshot snapshot = await uploadTask;
        String downloadUrl = await snapshot.ref.getDownloadURL();
        await _profileController.updateProfilePhoto(uid, downloadUrl);
        Get.snackbar('Succès', 'Photo de profil mise à jour avec succès');
      } catch (e) {
        Get.snackbar('Erreur', 'Échec du téléchargement de la photo de profil');
      }
    } else {
      Get.snackbar('Erreur', 'Aucune image sélectionnée');
    }
  }

  Widget _buildUserRoleInfo(AppUser user) {
    if (user.role == 'joueur') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Position: ${user.position ?? "Non spécifiée"}'),
          Text('Club Actuel: ${user.clubActuel ?? "Non spécifié"}'),
          Text('Nombre de Matchs: ${user.nombreDeMatchs ?? 0}'),
          Text('Buts: ${user.buts ?? 0}'),
          Text('Assistances: ${user.assistances ?? 0}'),
          if (user.performances != null) ...[
            const Text('Performances:'),
            ...user.performances!.entries.map((entry) => Text('${entry.key}: ${entry.value}')),
          ],
          Text('Biographie: ${user.bio ?? "Non spécifiée"}'),
        ],
      );
    } else if (user.role == 'club') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Localisation: ${user.nomClub ?? "Non spécifiée"}'),
          Text('Ligue: ${user.ligue ?? "Non spécifiée"}'),
          Text('Biographie: ${user.bio ?? "Non spécifiée"}'),
        ],
      );
    } else if (user.role == 'recruteur') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Entreprise: ${user.entreprise ?? "Non spécifiée"}'),
          Text('Nombre de Recrutements: ${user.nombreDeRecrutements ?? 0}'),
          Text('Biographie: ${user.bio ?? "Non spécifiée"}'),
        ],
      );
    } else if (user.role == 'fan') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Joueurs Suivis:'),
          if (user.joueursSuivis != null)
            ...user.joueursSuivis!.map((joueur) => Text(joueur.nom)),
          const Text('Clubs Suivis:'),
          if (user.clubsSuivis != null)
            ...user.clubsSuivis!.map((club) => Text(club.nomClub ?? 'Nom non spécifié')),
        ],
      );
    }
    return Container();
  }

  Widget _buildVideosGrid(List<dynamic> videosPubliees) {
    return GridView.builder(
      shrinkWrap: true,
      itemCount: videosPubliees.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
      ),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.network(
              videosPubliees[index].thumbnail,
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }

  void _showProfileOptions(BuildContext context, AppUser user) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Modifier le profil'),
            onTap: () {
              Navigator.pop(context);
              Get.to(() => EditProfileScreen(user: user));
            },
          ),
        ],
      ),
    );
  }
}
