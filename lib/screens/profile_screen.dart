
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/profile_controller.dart';
import '../models/user.dart';

class ProfileScreen extends StatelessWidget {
  final String uid;
  ProfileScreen({super.key, required this.uid});

  final ProfileController _profileController = Get.put(ProfileController());

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
          title: Text(user.name),
          centerTitle: true,
          actions: [IconButton(icon: const Icon(Icons.more_vert), onPressed: () {})],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Photo de profil
                CircleAvatar(
                  backgroundImage: NetworkImage(user.profilePhoto),
                  radius: 50,
                ),
                const Gap(10),
                Text(
                  user.name,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const Gap(10),

                // Affichage des informations selon le rôle de l'utilisateur
                if (user.role == 'joueur') ...[
                  Text('Équipe: ${user.team ?? "Non spécifié"}'),
                ] else if (user.role == 'club') ...[
                  Text('Nom du club: ${user.clubName ?? "Non spécifié"}'),
                ] else if (user.role == 'recruteur') ...[
                  Text('Bio: ${user.bio ?? "Non spécifiée"}'),
                ],

                const Gap(20),
                // Bouton de suivi/désuivi
                ElevatedButton(
                  onPressed: () {
                    _profileController.followUser();
                  },
                  child: Text(controller.user!.followers.contains(uid)
                      ? 'Se désabonner'
                      : 'Suivre'),
                ),

                const Gap(20),
                // Liste des vidéos si l'utilisateur en a
                if (user.videos != null && user.videos!.isNotEmpty) ...[
                  const Text('Vidéos publiées'),
                  GridView.builder(
                    shrinkWrap: true,
                    itemCount: user.videos!.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                    ),
                    itemBuilder: (context, index) {
                      return Image.network(user.videos![index]);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}
