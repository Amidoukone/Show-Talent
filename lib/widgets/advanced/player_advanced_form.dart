import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/profile_controller.dart';
import '../../models/user.dart';
import '../ad_button.dart';
import '../ad_feedback.dart';

class PlayerAdvancedForm extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;
  final bool autoCloseOnSave;
  final bool showSubmitButton;
  final bool showSectionTitle;
  final VoidCallback? onDirty;

  const PlayerAdvancedForm({
    super.key,
    required this.user,
    required this.profileController,
    this.autoCloseOnSave = true,
    this.showSubmitButton = true,
    this.showSectionTitle = true,
    this.onDirty,
  });

  @override
  State<PlayerAdvancedForm> createState() => PlayerAdvancedFormState();
}

class PlayerAdvancedFormState extends State<PlayerAdvancedForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _positionsController;
  late final TextEditingController _skillsController;
  late final TextEditingController _licenseController;

  String? _strongFoot;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final p = widget.user.playerProfile ?? {};
    final physical = (p['physical'] is Map) ? (p['physical'] as Map) : {};

    _heightController = TextEditingController(
      text: physical['heightCm']?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: physical['weightKg']?.toString() ?? '',
    );
    _strongFoot = physical['strongFoot']?.toString();
    _positionsController = TextEditingController(
      text: (p['positions'] as List?)?.join(', ') ?? '',
    );
    _skillsController = TextEditingController(
      text: (p['skills'] as List?)?.join(', ') ?? '',
    );
    _licenseController = TextEditingController(
      text: p['licenseNumber']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _positionsController.dispose();
    _skillsController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String> _csvToList(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<bool> save({bool showFeedback = true}) async {
    if (_saving) {
      return false;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return false;
    }

    setState(() => _saving = true);
    try {
      final positions = _csvToList(_positionsController.text);
      final skills = _csvToList(_skillsController.text);
      final patch = <String, dynamic>{
        if (positions.isNotEmpty) 'position': positions.first,
        'playerProfile': {
          'physical': {
            'heightCm': int.tryParse(_heightController.text.trim()),
            'weightKg': int.tryParse(_weightController.text.trim()),
            'strongFoot': _strongFoot,
          },
          'positions': positions,
          'skills': skills,
          'licenseNumber': _trimOrNull(_licenseController.text),
        },
      };

      try {
        await widget.profileController.updateProfilePatch(
          widget.user.uid,
          patch,
        );
      } on ProfileAccessRevokedException {
        if (showFeedback) {
          AdFeedback.error(
            'Sauvegarde refusée',
            'Votre session ne permet pas de modifier ce profil. Reconnectez-vous, puis réessayez.',
          );
        }
        return false;
      } catch (_) {
        if (showFeedback) {
          AdFeedback.error(
            'Sauvegarde impossible',
            'Les informations avancées du joueur n’ont pas été enregistrées.',
          );
        }
        return false;
      }

      if (widget.autoCloseOnSave && showFeedback) {
        Get.back();
      }

      if (showFeedback) {
        AdFeedback.success(
          'Profil mis à jour',
          'Les informations avancées du joueur ont été enregistrées.',
        );
      }

      return true;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      onChanged: widget.onDirty,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showSectionTitle) ...[
              const Text(
                'Profil joueur avancé',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _heightController,
              decoration: const InputDecoration(labelText: 'Taille (cm)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) {
                  return null;
                }
                final n = int.tryParse(t);
                if (n == null) {
                  return 'Nombre invalide';
                }
                if (n < 90 || n > 230) {
                  return 'Taille non valide';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _weightController,
              decoration: const InputDecoration(labelText: 'Poids (kg)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) {
                  return null;
                }
                final n = int.tryParse(t);
                if (n == null) {
                  return 'Nombre invalide';
                }
                if (n < 30 || n > 150) {
                  return 'Poids non valide';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: (_strongFoot == null || _strongFoot!.isEmpty)
                  ? null
                  : _strongFoot,
              items: const [
                DropdownMenuItem(value: 'right', child: Text('Droit')),
                DropdownMenuItem(value: 'left', child: Text('Gauche')),
                DropdownMenuItem(value: 'both', child: Text('Ambidextre')),
              ],
              onChanged: (v) => setState(() => _strongFoot = v),
              decoration: const InputDecoration(labelText: 'Pied fort'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _positionsController,
              decoration: const InputDecoration(
                labelText: 'Postes maîtrisés (séparés par des virgules)',
                hintText: 'Ex : Ailier droit, Milieu défensif, Latéral',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _skillsController,
              decoration: const InputDecoration(
                labelText: 'Qualités clés (séparées par des virgules)',
                hintText: 'Ex : Vitesse, Dribble, Qualité de centre',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _licenseController,
              decoration: const InputDecoration(
                labelText: 'Numéro de licence (facultatif)',
                hintText: 'Ex : LIC-FAF-2026-014',
              ),
            ),
            if (widget.showSubmitButton) ...[
              const SizedBox(height: 20),
              AdButton(
                leading: Icons.save_rounded,
                loading: _saving,
                label: 'Sauvegarder',
                onPressed: _saving ? null : () => save(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
