import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/profile_controller.dart';
import '../models/user.dart';
import 'profile_screen.dart';

class EditProfileScreen extends StatelessWidget {
  final AppUser user;
  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _teamController = TextEditingController();
  final TextEditingController _clubNameController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();
  final TextEditingController _entrepriseController = TextEditingController();
  final TextEditingController _ligueController = TextEditingController();
  final TextEditingController _nombreMatchsController = TextEditingController();
  final TextEditingController _butsController = TextEditingController();
  final TextEditingController _assistancesController = TextEditingController();
  final TextEditingController _nombreRecrutementsController = TextEditingController();

  EditProfileScreen({super.key, required this.user}) {
    _nomController.text = user.nom;
    _bioController.text = user.bio ?? '';
    _teamController.text = user.team ?? '';
    _clubNameController.text = user.nomClub ?? '';
    _positionController.text = user.position ?? '';
    _entrepriseController.text = user.entreprise ?? '';
    _ligueController.text = user.ligue ?? '';
    _nombreRecrutementsController.text = user.nombreDeRecrutements?.toString() ?? '0';
    _nombreMatchsController.text = user.nombreDeMatchs?.toString() ?? '0';
    _butsController.text = user.buts?.toString() ?? '0';
    _assistancesController.text = user.assistances?.toString() ?? '0';
  }

  final ProfileController _profileController = Get.find<ProfileController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier le profil'),
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextField(
                controller: _nomController,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 20),
              if (user.role != 'fan') ...[
                TextField(
                  controller: _bioController,
                  decoration: const InputDecoration(labelText: 'Biographie'),
                ),
                const SizedBox(height: 20),
              ],
              if (user.role == 'joueur' || user.role == 'coach') ...[
                TextField(
                  controller: _positionController,
                  decoration: const InputDecoration(labelText: 'Position'),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _teamController,
                  decoration: const InputDecoration(labelText: 'Club Actuel'),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nombreMatchsController,
                  decoration: const InputDecoration(labelText: 'Nombre de matchs'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _butsController,
                  decoration: const InputDecoration(labelText: 'Buts'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _assistancesController,
                  decoration: const InputDecoration(labelText: 'Assistances'),
                  keyboardType: TextInputType.number,
                ),
              ] else if (user.role == 'club') ...[
                TextField(
                  controller: _clubNameController,
                  decoration: const InputDecoration(labelText: 'Localisation'),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _ligueController,
                  decoration: const InputDecoration(labelText: 'Ligue'),
                ),
              ] else if (user.role == 'recruteur') ...[
                TextField(
                  controller: _entrepriseController,
                  decoration: const InputDecoration(labelText: 'Entreprise'),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nombreRecrutementsController,
                  decoration: const InputDecoration(labelText: 'Nombre de recrutements'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  // Sauvegarde les modifications
                  AppUser updatedUser = AppUser(
                    uid: user.uid,
                    nom: _nomController.text,
                    email: user.email,
                    role: user.role,
                    photoProfil: user.photoProfil,
                    estActif: user.estActif,
                    followers: user.followers,
                    followings: user.followings,
                    dateInscription: user.dateInscription,
                    dernierLogin: user.dernierLogin,
                    bio: _bioController.text,
                    team: _teamController.text.isEmpty ? null : _teamController.text,
                    nomClub: _clubNameController.text.isEmpty ? null : _clubNameController.text,
                    position: _positionController.text.isEmpty ? null : _positionController.text,
                    entreprise: _entrepriseController.text.isEmpty ? null : _entrepriseController.text,
                    ligue: _ligueController.text.isEmpty ? null : _ligueController.text,
                    nombreDeMatchs: int.tryParse(_nombreMatchsController.text) ?? 0,
                    buts: int.tryParse(_butsController.text) ?? 0,
                    assistances: int.tryParse(_assistancesController.text) ?? 0,
                    nombreDeRecrutements: int.tryParse(_nombreRecrutementsController.text) ?? 0,
                    videosPubliees: user.videosPubliees,
                  );
                  await _profileController.updateUserProfile(updatedUser);

                  // Redirection vers la page de profil après la sauvegarde
                  Get.off(() => ProfileScreen(uid: user.uid));
                  Get.snackbar('Succès', 'Profil mis à jour avec succès');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF214D4F),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12.0,
                    horizontal: 24.0,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: const Text(
                  'Sauvegarder',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
