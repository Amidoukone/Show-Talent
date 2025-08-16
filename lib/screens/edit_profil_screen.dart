import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/profile_controller.dart';
import '../models/user.dart';
import 'profile_screen.dart';

class EditProfileScreen extends StatelessWidget {
  final AppUser user;
  final ProfileController profileController;

  // Couleurs & styles
  static const kPrimary = Color(0xFF214D4F);
  static const kAccent = Color(0xFF00BFA6);
  static const kDanger = Color(0xFFE53935);
  static const kSurface = Color(0xFFF7FAFA);

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

  EditProfileScreen({
    super.key,
    required this.user,
    required this.profileController,
  }) {
    _nomController.text = user.nom;
    _bioController.text = user.bio ?? '';
    _teamController.text = user.team ?? '';
    _clubNameController.text = user.nomClub ?? '';
    _positionController.text = user.position ?? '';
    _entrepriseController.text = user.entreprise ?? '';
    _ligueController.text = user.ligue ?? '';
    _nombreRecrutementsController.text =
        user.nombreDeRecrutements?.toString() ?? '0';
    _nombreMatchsController.text = user.nombreDeMatchs?.toString() ?? '0';
    _butsController.text = user.buts?.toString() ?? '0';
    _assistancesController.text = user.assistances?.toString() ?? '0';
  }

  @override
  Widget build(BuildContext context) {
    final inputTheme = _inputDecorationTheme(context);

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Modifier le profil'),
        backgroundColor: kPrimary,
        elevation: 1,
        centerTitle: true,
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: inputTheme,
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white, // texte + icône en blanc
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimary,
              side: const BorderSide(color: kPrimary, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: kPrimary),
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (_, c) => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionCard(
                        title: 'Informations générales',
                        icon: Icons.badge_rounded,
                        child: Column(
                          children: [
                            _buildTextField(
                              controller: _nomController,
                              label: 'Nom',
                              icon: Icons.person_outline,
                            ),
                            if (user.role != 'fan') ...[
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _bioController,
                                label: 'Infos Professionnelles',
                                icon: Icons.info_outline,
                                maxLines: 3,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (user.role == 'joueur' || user.role == 'coach')
                        _SectionCard(
                          title: user.role == 'coach'
                              ? 'Informations coach'
                              : 'Informations joueur',
                          icon: Icons.sports_soccer_outlined,
                          child: Column(
                            children: [
                              _buildTextField(
                                controller: _positionController,
                                label: 'Position',
                                icon: Icons.location_searching_outlined,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _teamController,
                                label: 'Club Actuel',
                                icon: Icons.flag_outlined,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _nombreMatchsController,
                                      label: 'Nombre de matchs',
                                      icon: Icons.scoreboard_outlined,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _butsController,
                                      label: 'Buts',
                                      icon: Icons.sports_soccer,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _assistancesController,
                                label: 'Assistances',
                                icon: Icons.group_add_outlined,
                                keyboardType: TextInputType.number,
                              ),
                            ],
                          ),
                        )
                      else if (user.role == 'club')
                        _SectionCard(
                          title: 'Informations club',
                          icon: Icons.stadium_outlined,
                          child: Column(
                            children: [
                              _buildTextField(
                                controller: _clubNameController,
                                label: 'Situation géographique',
                                icon: Icons.place_outlined,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _ligueController,
                                label: 'Ligue',
                                icon: Icons.emoji_events_outlined,
                              ),
                            ],
                          ),
                        )
                      else if (user.role == 'recruteur')
                        _SectionCard(
                          title: 'Informations recruteur',
                          icon: Icons.search_rounded,
                          child: Column(
                            children: [
                              _buildTextField(
                                controller: _entrepriseController,
                                label: 'Entreprise',
                                icon: Icons.apartment_outlined,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _nombreRecrutementsController,
                                label: 'Nombre de recrutements',
                                icon: Icons.how_to_reg_outlined,
                                keyboardType: TextInputType.number,
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),

                      // Section CV (joueur)
                      if (user.role == 'joueur') ...[
                        CvUploaderSection(
                          user: user,
                          profileController: profileController,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Bouton Sauvegarder (full width)
                      ElevatedButton.icon(
                        onPressed: () async {
                          final updatedUser = AppUser(
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
                            team: _teamController.text.isEmpty
                                ? null
                                : _teamController.text,
                            nomClub: _clubNameController.text.isEmpty
                                ? null
                                : _clubNameController.text,
                            position: _positionController.text.isEmpty
                                ? null
                                : _positionController.text,
                            entreprise: _entrepriseController.text.isEmpty
                                ? null
                                : _entrepriseController.text,
                            ligue: _ligueController.text.isEmpty
                                ? null
                                : _ligueController.text,
                            nombreDeMatchs:
                                int.tryParse(_nombreMatchsController.text) ?? 0,
                            buts: int.tryParse(_butsController.text) ?? 0,
                            assistances:
                                int.tryParse(_assistancesController.text) ?? 0,
                            nombreDeRecrutements:
                                int.tryParse(_nombreRecrutementsController.text) ??
                                    0,
                            videosPubliees: user.videosPubliees,
                            followersList: user.followersList,
                            followingsList: user.followingsList,
                            cvUrl: user.cvUrl,
                            estBloque: user.estBloque,
                            emailVerified: user.emailVerified,
                          );

                          await profileController.updateUserProfile(updatedUser);
                          Get.off(() => ProfileScreen(uid: user.uid));
                          Get.snackbar('Succès', 'Profil mis à jour avec succès');
                        },
                        icon: const Icon(Icons.save_rounded),
                        label: const Text(
                          'Sauvegarder',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- UI helpers ----

  InputDecorationTheme _inputDecorationTheme(BuildContext context) {
    final base = Theme.of(context).inputDecorationTheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFB5C7C7)),
    );
    final focused = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kPrimary, width: 1.6),
    );

    return base.copyWith(
      filled: true,
      fillColor: Colors.white,
      border: border,
      enabledBorder: border,
      focusedBorder: focused,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(color: Colors.black87),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: kPrimary),
      ),
    );
  }
}

// ---------------------------
// CV Uploader (stylisé)
// ---------------------------
class CvUploaderSection extends StatelessWidget {
  final AppUser user;
  final ProfileController profileController;

  static const kPrimary = EditProfileScreen.kPrimary;
  static const kAccent = EditProfileScreen.kAccent;
  static const kDanger = EditProfileScreen.kDanger;

  const CvUploaderSection({
    super.key,
    required this.user,
    required this.profileController,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'CV (PDF)',
      icon: Icons.picture_as_pdf_outlined,
      trailing: user.cvUrl != null
          ? const Chip(
              label: Text('Disponible'),
              avatar: Icon(Icons.check_circle, color: Colors.white, size: 18),
              backgroundColor: Colors.green,
              labelStyle: TextStyle(color: Colors.white),
            )
          : const Chip(
              label: Text('Aucun CV'),
              avatar: Icon(Icons.info_outline, color: Colors.white, size: 18),
              backgroundColor: Colors.orange,
              labelStyle: TextStyle(color: Colors.white),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['pdf'],
              );
              if (result != null && result.files.single.path != null) {
                await profileController.uploadCvPdf(
                  user.uid,
                  File(result.files.single.path!),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white, // texte & icône en blanc
            ),
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(
              user.cvUrl == null ? 'Ajouter un CV' : 'Remplacer le CV',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (user.cvUrl != null) ...[
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () async {
                await profileController.deleteCv(user.uid);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kDanger,
                foregroundColor: Colors.white, // texte & icône en blanc
              ),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Supprimer le CV',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------
// Carte de section réutilisable
// ---------------------------
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.8,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: EditProfileScreen.kPrimary.withOpacity(0.1),
                  child: Icon(icon, color: EditProfileScreen.kPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
