import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/profile_controller.dart';
import 'package:adfoot/theme/ad_colors.dart';

import '../models/user.dart';
import 'profile_screen.dart';

class EditProfileScreen extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;

  const EditProfileScreen({
    super.key,
    required this.user,
    required this.profileController,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // --- Couleurs ---
  static const kPrimary = AdColors.brand;
  static const kAccent = AdColors.accent;
  static const kDanger = AdColors.error;
  static const kSurface = AdColors.surface;

  final _formKey = GlobalKey<FormState>();

  // --- Controllers de texte ---
  late final TextEditingController _nomController;
  late final TextEditingController _bioController;
  late final TextEditingController _phoneController;
  late final TextEditingController _languagesController;

  // Joueur
  late final TextEditingController _teamController;
  late final TextEditingController _positionController;
  late final TextEditingController _nombreMatchsController;
  late final TextEditingController _butsController;
  late final TextEditingController _assistancesController;

  // Club
  late final TextEditingController _clubNameController;
  late final TextEditingController _ligueController;

  // Recruteur
  late final TextEditingController _entrepriseController;
  late final TextEditingController _nombreRecrutementsController;

  // Performances (Map<String,double>) => édition simple (champ multi-lignes)
  // Format: "vitesse=8.5\nfinition=7\n..."
  late final TextEditingController _performancesController;

  bool _saving = false;

  AppUser get user => widget.user;
  ProfileController get profileController => widget.profileController;

  @override
  void initState() {
    super.initState();

    _nomController = TextEditingController(text: user.nom);
    _bioController = TextEditingController(text: user.bio ?? '');
    _phoneController = TextEditingController(text: user.phone ?? '');

    _teamController = TextEditingController(text: user.team ?? '');
    _clubNameController = TextEditingController(text: user.nomClub ?? '');
    _positionController = TextEditingController(text: user.position ?? '');
    _entrepriseController = TextEditingController(text: user.entreprise ?? '');
    _ligueController = TextEditingController(text: user.ligue ?? '');
    _languagesController = TextEditingController(
      text: user.languages?.join(', ') ?? '',
    );

    _nombreRecrutementsController = TextEditingController(
        text: (user.nombreDeRecrutements ?? 0).toString());
    _nombreMatchsController =
        TextEditingController(text: (user.nombreDeMatchs ?? 0).toString());
    _butsController = TextEditingController(text: (user.buts ?? 0).toString());
    _assistancesController =
        TextEditingController(text: (user.assistances ?? 0).toString());

    _performancesController = TextEditingController(
      text: _performancesToText(user.performances),
    );
  }

  @override
  void dispose() {
    _nomController.dispose();
    _bioController.dispose();
    _phoneController.dispose();

    _teamController.dispose();
    _positionController.dispose();
    _nombreMatchsController.dispose();
    _butsController.dispose();
    _assistancesController.dispose();

    _clubNameController.dispose();
    _ligueController.dispose();

    _entrepriseController.dispose();
    _nombreRecrutementsController.dispose();

    _performancesController.dispose();
    super.dispose();
  }

  // ---- Helpers parsing ----

  String _trimOrEmpty(String v) => v.trim();

  String? _trimOrNull(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  int? _intOrNull(String v) {
    final t = v.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  int? _intOrNullClamped(String v, {int? min, int? max}) {
    final n = _intOrNull(v);
    if (n == null) return null;
    int x = n;
    if (min != null && x < min) x = min;
    if (max != null && x > max) x = max;
    return x;
  }

  Map<String, double>? _parsePerformances(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final lines = text.split('\n');
    final Map<String, double> out = {};

    for (final line in lines) {
      final l = line.trim();
      if (l.isEmpty) continue;
      // support: key=value OR key: value
      final sep = l.contains('=') ? '=' : (l.contains(':') ? ':' : null);
      if (sep == null) continue;

      final parts = l.split(sep);
      if (parts.length < 2) continue;

      final key = parts[0].trim();
      final valStr = parts.sublist(1).join(sep).trim(); // au cas où
      final val = double.tryParse(valStr.replaceAll(',', '.'));

      if (key.isEmpty || val == null) continue;
      out[key] = val;
    }

    return out.isEmpty ? null : out;
  }

  String _performancesToText(Map<String, double>? perf) {
    if (perf == null || perf.isEmpty) return '';
    final keys = perf.keys.toList()..sort();
    return keys.map((k) => '$k=${perf[k]}').join('\n');
  }

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
    String? Function(String?)? validator,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: kPrimary),
      ),
    );
  }

  bool get _isPlayer => user.role == 'joueur' || user.role == 'coach';
  bool get _isClub => user.role == 'club';
  bool get _isRecruiter => user.role == 'recruteur';

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving) return;

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      final Map<String, dynamic> patch = {};

      // =====================
      // Base commune
      // =====================
      patch['nom'] = _trimOrEmpty(_nomController.text);
      patch['phone'] = _trimOrNull(_phoneController.text);
      patch['languages'] = _languagesController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      patch['bio'] = _trimOrNull(_bioController.text);

      // =====================
      // Joueur / Coach (MVP)
      // =====================
      if (_isPlayer) {
        patch['position'] = _trimOrNull(_positionController.text);
        patch['team'] = _trimOrNull(_teamController.text);
        patch['nombreDeMatchs'] =
            _intOrNullClamped(_nombreMatchsController.text, min: 0, max: 9999);
        patch['buts'] =
            _intOrNullClamped(_butsController.text, min: 0, max: 9999);
        patch['assistances'] =
            _intOrNullClamped(_assistancesController.text, min: 0, max: 9999);

        patch['performances'] =
            _parsePerformances(_performancesController.text);
      }

      // =====================
      // Club (MVP)
      // =====================
      if (_isClub) {
        patch['nomClub'] = _trimOrNull(_clubNameController.text);
        patch['ligue'] = _trimOrNull(_ligueController.text);
      }

      // =====================
      // Recruteur (MVP)
      // =====================
      if (_isRecruiter) {
        patch['entreprise'] = _trimOrNull(_entrepriseController.text);
        patch['nombreDeRecrutements'] = _intOrNullClamped(
          _nombreRecrutementsController.text,
          min: 0,
          max: 9999,
        );
      }

      // 🔥 PATCH SAFE
      await profileController.updateProfilePatch(user.uid, patch);

      Get.off(() => ProfileScreen(uid: user.uid));
      Get.snackbar(
        'Succès',
        'Profil mis à jour',
        backgroundColor: kAccent,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'Erreur',
        'Impossible de sauvegarder : $e',
        backgroundColor: kDanger,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
              foregroundColor: Colors.white,
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // --- SECTION INFOS GÉNÉRALES ---
                        _SectionCard(
                          title: 'Informations générales',
                          icon: Icons.badge_rounded,
                          child: Column(
                            children: [
                              _buildTextField(
                                controller: _nomController,
                                label: 'Nom complet',
                                icon: Icons.person_outline,
                                validator: (v) {
                                  final t = (v ?? '').trim();
                                  if (t.isEmpty) return 'Le nom est requis';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _phoneController,
                                label: 'Numéro de téléphone',
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _languagesController,
                                label: 'Langues',
                                icon: Icons.language_outlined,
                                hint: 'Français, Anglais, Espagnol',
                              ),
                              if (user.role != 'fan') ...[
                                const SizedBox(height: 12),
                                _buildTextField(
                                  controller: _bioController,
                                  label: 'Bio / Infos',
                                  icon: Icons.info_outline,
                                  maxLines: 3,
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),
                        // --- SECTION SPÉCIFIQUE AU RÔLE ---
                        if (_isPlayer)
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
                                  hint: 'Ex: Ailier droit, MDC, Gardien...',
                                ),
                                const SizedBox(height: 12),
                                _buildTextField(
                                  controller: _teamController,
                                  label: 'Club actuel',
                                  icon: Icons.flag_outlined,
                                  hint: 'Ex: AS Bamako',
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: _nombreMatchsController,
                                        label: 'Matchs',
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
                                  label: 'Passes décisives',
                                  icon: Icons.group_add_outlined,
                                  keyboardType: TextInputType.number,
                                ),
                                const SizedBox(height: 12),

                                // ✅ Performances (Map<String,double>) — simple et safe
                                _buildTextField(
                                  controller: _performancesController,
                                  label: 'Performances (optionnel)',
                                  icon: Icons.insights_outlined,
                                  maxLines: 4,
                                  hint: 'Format:\n'
                                      'vitesse=8.5\n'
                                      'finition=7\n'
                                      'jeu_aerien=6.5',
                                ),
                              ],
                            ),
                          )
                        else if (_isClub)
                          _SectionCard(
                            title: 'Informations club',
                            icon: Icons.stadium_outlined,
                            child: Column(
                              children: [
                                _buildTextField(
                                  controller: _clubNameController,
                                  label: 'Nom du club',
                                  icon: Icons.apartment_outlined,
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
                        else if (_isRecruiter)
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

                        // --- CV JOUEUR ---
                        if (user.role == 'joueur') ...[
                          CvUploaderSection(
                            user: user,
                            profileController: profileController,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // --- BOUTON SAUVEGARDER ---
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded),
                          label: Text(
                            _saving ? 'Sauvegarde...' : 'Sauvegarder',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
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
      ),
    );
  }
}

// ---------------------------
// CV UPLOADER
// ---------------------------
class CvUploaderSection extends StatelessWidget {
  final AppUser user;
  final ProfileController profileController;

  static const kPrimary = _EditProfileScreenState.kPrimary;
  static const kAccent = _EditProfileScreenState.kAccent;
  static const kDanger = _EditProfileScreenState.kDanger;

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
              foregroundColor: Colors.white,
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
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text(
                'Supprimer le CV',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------
// SECTION CARD
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
                  backgroundColor:
                      _EditProfileScreenState.kPrimary.withValues(alpha: 0.1),
                  child: Icon(icon, color: _EditProfileScreenState.kPrimary),
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
