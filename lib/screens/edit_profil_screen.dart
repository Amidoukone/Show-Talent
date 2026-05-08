import 'dart:io';
import 'dart:typed_data';

import 'package:adfoot/controller/profile_controller.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
  static const kPrimary = AdColors.brand;
  static const kAccent = AdColors.accent;
  static const kDanger = AdColors.error;
  static const kSurface = AdColors.surface;

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nomController;
  late final TextEditingController _bioController;
  late final TextEditingController _phoneController;
  late final TextEditingController _languagesController;

  late final TextEditingController _teamController;
  late final TextEditingController _positionController;
  late final TextEditingController _nombreMatchsController;
  late final TextEditingController _butsController;
  late final TextEditingController _assistancesController;
  DateTime? _selectedBirthDate;

  late final TextEditingController _clubNameController;
  late final TextEditingController _ligueController;

  late final TextEditingController _entrepriseController;
  late final TextEditingController _nombreRecrutementsController;

  late final TextEditingController _performancesController;

  bool _saving = false;

  AppUser get user => widget.user;
  ProfileController get profileController => widget.profileController;

  bool get _isPlayer => user.role == 'joueur' || user.role == 'coach';
  bool get _isClub => user.role == 'club';
  bool get _isRecruiter => user.isRecruiter;

  @override
  void initState() {
    super.initState();

    _nomController = TextEditingController(text: user.nom);
    _bioController = TextEditingController(text: user.bio ?? '');
    _phoneController = TextEditingController(text: user.phone ?? '');
    _languagesController = TextEditingController(
      text: user.languages?.join(', ') ?? '',
    );

    _teamController = TextEditingController(text: user.team ?? '');
    _positionController = TextEditingController(text: user.position ?? '');
    _nombreMatchsController =
        TextEditingController(text: (user.nombreDeMatchs ?? 0).toString());
    _butsController = TextEditingController(text: (user.buts ?? 0).toString());
    _assistancesController =
        TextEditingController(text: (user.assistances ?? 0).toString());
    _selectedBirthDate = user.birthDate;

    _clubNameController = TextEditingController(text: user.nomClub ?? '');
    _ligueController = TextEditingController(text: user.ligue ?? '');

    _entrepriseController = TextEditingController(text: user.entreprise ?? '');
    _nombreRecrutementsController = TextEditingController(
      text: (user.nombreDeRecrutements ?? 0).toString(),
    );

    _performancesController = TextEditingController(
      text: _performancesToText(user.performances),
    );
  }

  @override
  void dispose() {
    _nomController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _languagesController.dispose();
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

  String _trimOrEmpty(String v) => v.trim();

  String? _trimOrNull(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  int? _intOrNull(String v) {
    final t = v.trim();
    if (t.isEmpty) {
      return null;
    }
    return int.tryParse(t);
  }

  int? _intOrNullClamped(String v, {int? min, int? max}) {
    final n = _intOrNull(v);
    if (n == null) {
      return null;
    }
    int x = n;
    if (min != null && x < min) {
      x = min;
    }
    if (max != null && x > max) {
      x = max;
    }
    return x;
  }

  String? _validateOptionalNonNegativeInt(String? value, {int max = 9999}) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final number = int.tryParse(text);
    if (number == null) {
      return 'Veuillez saisir un nombre valide.';
    }
    if (number < 0) {
      return 'La valeur doit être positive.';
    }
    if (number > max) {
      return 'La valeur maximale est $max.';
    }
    return null;
  }

  Map<String, double>? _parsePerformances(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }

    final lines = text.split('\n');
    final out = <String, double>{};

    for (final line in lines) {
      final l = line.trim();
      if (l.isEmpty) {
        continue;
      }

      final sep = l.contains('=') ? '=' : (l.contains(':') ? ':' : null);
      if (sep == null) {
        continue;
      }

      final parts = l.split(sep);
      if (parts.length < 2) {
        continue;
      }

      final key = parts[0].trim();
      final valStr = parts.sublist(1).join(sep).trim();
      final val = double.tryParse(valStr.replaceAll(',', '.'));

      if (key.isEmpty || val == null) {
        continue;
      }
      out[key] = val;
    }

    return out.isEmpty ? null : out;
  }

  String _performancesToText(Map<String, double>? perf) {
    if (perf == null || perf.isEmpty) {
      return '';
    }
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
      fillColor: AdColors.surfaceCard,
      border: border,
      enabledBorder: border,
      focusedBorder: focused,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(color: AdColors.onSurfaceMuted),
    );
  }

  Widget _buildHeader({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: kPrimary.withValues(alpha: 0.12),
            foregroundColor: kPrimary,
            child: Icon(icon),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
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

  Widget _buildBirthDateField(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _pickBirthDate,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date de naissance',
          prefixIcon: const Icon(Icons.cake_outlined, color: kPrimary),
          suffixIcon: _selectedBirthDate != null
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _selectedBirthDate = null),
                  tooltip: 'Effacer',
                )
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedBirthDate != null
                    ? _formatBirthDate(_selectedBirthDate!)
                    : 'Ajoute ta date de naissance',
                style: TextStyle(
                  color: _selectedBirthDate != null
                      ? AdColors.onSurface
                      : AdColors.onSurfaceMuted,
                  fontWeight:
                      _selectedBirthDate != null ? FontWeight.w600 : null,
                ),
              ),
            ),
            const Icon(Icons.edit_calendar_outlined, color: kPrimary),
          ],
        ),
      ),
    );
  }

  String _formatBirthDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initial =
        _selectedBirthDate ?? DateTime(now.year - 18, now.month, now.day);
    final earliest = DateTime(now.year - 60);
    final latest = DateTime(now.year - 10, now.month, now.day);

    DateTime initialDate = initial;
    if (initialDate.isAfter(latest)) {
      initialDate = latest;
    }
    if (initialDate.isBefore(earliest)) {
      initialDate = earliest;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: earliest,
      lastDate: latest,
      helpText: 'Choisir ta date de naissance',
      confirmText: 'Valider',
      cancelText: 'Annuler',
    );

    if (picked != null) {
      setState(() => _selectedBirthDate = picked);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _saving = true);

    try {
      final patch = <String, dynamic>{};

      patch['nom'] = _trimOrEmpty(_nomController.text);

      final phone = _trimOrNull(_phoneController.text);
      if (phone != null) {
        patch['phone'] = phone;
      } else if ((user.phone?.isNotEmpty ?? false)) {
        patch['phone'] = ProfileController.deleteField;
      }

      final languages = _languagesController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (languages.isNotEmpty) {
        patch['languages'] = languages;
      } else if (user.languages?.isNotEmpty == true) {
        patch['languages'] = ProfileController.deleteField;
      }

      final bio = _trimOrNull(_bioController.text);
      if (bio != null) {
        patch['bio'] = bio;
      } else if ((user.bio?.isNotEmpty ?? false)) {
        patch['bio'] = ProfileController.deleteField;
      }

      if (_isPlayer) {
        if (_selectedBirthDate != null) {
          patch['birthDate'] = _selectedBirthDate;
        } else if (user.birthDate != null) {
          patch['birthDate'] = ProfileController.deleteField;
        }

        final position = _trimOrNull(_positionController.text);
        if (position != null) {
          patch['position'] = position;
        } else if ((user.position?.isNotEmpty ?? false)) {
          patch['position'] = ProfileController.deleteField;
        }

        final team = _trimOrNull(_teamController.text);
        if (team != null) {
          patch['team'] = team;
        } else if ((user.team?.isNotEmpty ?? false)) {
          patch['team'] = ProfileController.deleteField;
        }

        final matches =
            _intOrNullClamped(_nombreMatchsController.text, min: 0, max: 9999);
        if (matches != null) {
          patch['nombreDeMatchs'] = matches;
        } else if (user.nombreDeMatchs != null) {
          patch['nombreDeMatchs'] = ProfileController.deleteField;
        }

        final goals =
            _intOrNullClamped(_butsController.text, min: 0, max: 9999);
        if (goals != null) {
          patch['buts'] = goals;
        } else if (user.buts != null) {
          patch['buts'] = ProfileController.deleteField;
        }

        final assists =
            _intOrNullClamped(_assistancesController.text, min: 0, max: 9999);
        if (assists != null) {
          patch['assistances'] = assists;
        } else if (user.assistances != null) {
          patch['assistances'] = ProfileController.deleteField;
        }

        final performances = _parsePerformances(_performancesController.text);
        if (performances != null) {
          patch['performances'] = performances;
        } else if (user.performances?.isNotEmpty == true) {
          patch['performances'] = ProfileController.deleteField;
        }
      }

      if (_isClub) {
        final clubName = _trimOrNull(_clubNameController.text);
        if (clubName != null) {
          patch['nomClub'] = clubName;
        } else if ((user.nomClub?.isNotEmpty ?? false)) {
          patch['nomClub'] = ProfileController.deleteField;
        }

        final ligue = _trimOrNull(_ligueController.text);
        if (ligue != null) {
          patch['ligue'] = ligue;
        } else if ((user.ligue?.isNotEmpty ?? false)) {
          patch['ligue'] = ProfileController.deleteField;
        }
      }

      if (_isRecruiter) {
        final entreprise = _trimOrNull(_entrepriseController.text);
        if (entreprise != null) {
          patch['entreprise'] = entreprise;
        } else if ((user.entreprise?.isNotEmpty ?? false)) {
          patch['entreprise'] = ProfileController.deleteField;
        }

        final recruitments = _intOrNullClamped(
          _nombreRecrutementsController.text,
          min: 0,
          max: 9999,
        );
        if (recruitments != null) {
          patch['nombreDeRecrutements'] = recruitments;
        } else if (user.nombreDeRecrutements != null) {
          patch['nombreDeRecrutements'] = ProfileController.deleteField;
        }
      }

      await profileController.updateProfilePatch(
        user.uid,
        patch,
        refreshGlobalUser: false,
      );

      if (!mounted) {
        return;
      }

      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        Get.off(() => ProfileScreen(uid: user.uid));
      }

      AdFeedback.success('Succès', 'Profil mis à jour.');
    } on ProfileAccessRevokedException {
      return;
    } catch (e) {
      debugPrint('EditProfile _save error: $e');
      AdFeedback.error(
        'Erreur',
        'Impossible de sauvegarder les modifications.',
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inputTheme = _inputDecorationTheme(context);
    final headerTitle = _isPlayer
        ? 'Profil sportif'
        : _isClub
            ? 'Profil club'
            : _isRecruiter
                ? 'Profil recruteur'
                : 'Profil';
    final headerSubtitle = _isPlayer
        ? 'Mettez à jour vos informations publiques et vos indicateurs essentiels dans un écran plus lisible.'
        : _isClub
            ? 'Rassemblez les informations visibles de votre structure dans une présentation plus claire.'
            : _isRecruiter
                ? 'Gardez vos informations de contact et de recrutement dans un parcours plus propre.'
                : 'Mettez à jour les informations visibles de votre profil.';

    return Scaffold(
      backgroundColor: kSurface,
      appBar: const AdAppBar(title: 'Modifier le profil'),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(
                          context: context,
                          title: headerTitle,
                          subtitle: headerSubtitle,
                          icon: _isPlayer
                              ? Icons.person_pin_circle_outlined
                              : _isClub
                                  ? Icons.groups_outlined
                                  : _isRecruiter
                                      ? Icons.badge_outlined
                                      : Icons.person_outline,
                        ),
                        const SizedBox(height: 16),
                        _SectionCard(
                          title: 'Informations générales',
                          subtitle:
                              'Nom, contact, langues, bio et informations de base du profil.',
                          icon: Icons.badge_rounded,
                          child: Column(
                            children: [
                              _buildTextField(
                                controller: _nomController,
                                label: 'Nom complet',
                                icon: Icons.person_outline,
                                validator: (v) {
                                  final t = (v ?? '').trim();
                                  if (t.isEmpty) {
                                    return 'Le nom est requis';
                                  }
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
                              if (_isPlayer) ...[
                                const SizedBox(height: 12),
                                _buildBirthDateField(context),
                              ],
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
                        if (_isPlayer)
                          _SectionCard(
                            title: user.role == 'coach'
                                ? 'Informations coach'
                                : 'Informations joueur',
                            subtitle:
                                'Position, club actuel, statistiques et performances visibles.',
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
                                        validator:
                                            _validateOptionalNonNegativeInt,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: _butsController,
                                        label: 'Buts',
                                        icon: Icons.sports_soccer,
                                        keyboardType: TextInputType.number,
                                        validator:
                                            _validateOptionalNonNegativeInt,
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
                                  validator: _validateOptionalNonNegativeInt,
                                ),
                                const SizedBox(height: 12),
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
                            subtitle:
                                'Nom du club et compétition ou ligue de référence.',
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
                            title: 'Informations recruteur / agent',
                            subtitle:
                                'Entreprise et volume de recrutements déjà réalisés.',
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
                                  validator: _validateOptionalNonNegativeInt,
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (user.role == 'joueur') ...[
                          CvUploaderSection(
                            user: user,
                            profileController: profileController,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton.icon(
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
              _saving ? 'Sauvegarde...' : 'Enregistrer',
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
        ),
      ),
    );
  }
}

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
      subtitle:
          'Ajoutez votre CV pour compléter votre présentation professionnelle.',
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
                withData: true,
              );
              if (result != null) {
                final pickedFile = result.files.single;
                final Uint8List? bytes = pickedFile.bytes;
                final String? path = pickedFile.path;
                final String fileName = pickedFile.name.isNotEmpty
                    ? pickedFile.name
                    : 'cv_${DateTime.now().millisecondsSinceEpoch}.pdf';

                try {
                  await profileController.uploadCvPdf(
                    user.uid,
                    pdfBytes: bytes,
                    pdfFile: path != null && path.isNotEmpty ? File(path) : null,
                    fileName: fileName.toLowerCase().endsWith('.pdf')
                        ? fileName
                        : '$fileName.pdf',
                  );
                } on ProfileAccessRevokedException {
                  return;
                }
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
                try {
                  await profileController.deleteCv(user.uid);
                } on ProfileAccessRevokedException {
                  return;
                }
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

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      _EditProfileScreenState.kPrimary.withValues(alpha: 0.1),
                  child: Icon(icon, color: _EditProfileScreenState.kPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
