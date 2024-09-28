import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/profile_controller.dart';
import 'package:show_talent/screens/edit_profil_screen.dart';
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
          title: Text(user.nom),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {
                _showProfileOptions(context, user);
              },
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Photo de profil
                CircleAvatar(
                  backgroundImage: NetworkImage(user.photoProfil),
                  radius: 50,
                ),
                const Gap(10),
                Text(
                  user.nom,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const Gap(10),

                // Affichage des followers et followings pour tous les rôles sauf fan
                if (user.role != 'fan') ...[
                  Text('Followers: ${user.followers}'),
                  Text('Followings: ${user.followings}'),
                  const Gap(10),
                ],

                // Affichage des informations spécifiques au rôle
                if (user.role == 'joueur') ...[
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
                ] else if (user.role == 'club') ...[
                  Text('Localisation: ${user.nomClub ?? "Non spécifiée"}'),  // Remplacer par localisation
                  Text('Ligue: ${user.ligue ?? "Non spécifiée"}'),
                  Text('Biographie: ${user.bio ?? "Non spécifiée"}'),
                ] else if (user.role == 'recruteur') ...[
                  Text('Entreprise: ${user.entreprise ?? "Non spécifiée"}'),
                  Text('Nombre de Recrutements: ${user.nombreDeRecrutements ?? 0}'),
                  Text('Biographie: ${user.bio ?? "Non spécifiée"}'),
                ] else if (user.role == 'fan') ...[
                  const Text('Joueurs Suivis:'),
                  if (user.joueursSuivis != null)
                    for (var joueur in user.joueursSuivis!) Text(joueur.nom),
                  const Text('Clubs Suivis:'),
                  if (user.clubsSuivis != null)
                    for (var club in user.clubsSuivis!) Text(club.nomClub ?? 'Nom non spécifié'),
                ],

                const Gap(20),
                // Bouton de suivi/désuivi
                if (user.role != 'fan') ElevatedButton(
                  onPressed: () {
                    _profileController.followUser();
                  },
                  child: Text(
                    controller.user!.followers > 0 ? 'Se désabonner' : 'Suivre',
                  ),
                ),

                const Gap(20),
                // Liste des vidéos publiées (uniquement pour les joueurs)
                if (user.role == 'joueur' && user.videosPubliees != null && user.videosPubliees!.isNotEmpty) ...[
                  const Text('Vidéos publiées'),
                  GridView.builder(
                    shrinkWrap: true,
                    itemCount: user.videosPubliees!.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                    ),
                    itemBuilder: (context, index) {
                      return Image.network(user.videosPubliees![index].thumbnail);
                    },
                  ),
                ] else if (user.role == 'joueur') ...[
                  const Text('Pas de vidéos publiées.'),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  // Affiche les options de modification du profil
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
