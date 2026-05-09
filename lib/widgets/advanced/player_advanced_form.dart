import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/profile_controller.dart';
import '../../models/user.dart';

class PlayerAdvancedForm extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;
  final bool autoCloseOnSave;
  final bool showSubmitButton;
  final bool showSectionTitle;

  const PlayerAdvancedForm({
    super.key,
    required this.user,
    required this.profileController,
    this.autoCloseOnSave = true,
    this.showSubmitButton = true,
    this.showSectionTitle = true,
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

  String? _strongFoot;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final p = widget.user.playerProfile ?? {};
    final physical = (p['physical'] is Map) ? (p['physical'] as Map) : {};

    _heightController =
        TextEditingController(text: physical['heightCm']?.toString() ?? '');
    _weightController =
        TextEditingController(text: physical['weightKg']?.toString() ?? '');
    _strongFoot = physical['strongFoot']?.toString();
    _positionsController = TextEditingController(
      text: (p['positions'] as List?)?.join(', ') ?? '',
    );
    _skillsController = TextEditingController(
      text: (p['skills'] as List?)?.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _positionsController.dispose();
    _skillsController.dispose();
    super.dispose();
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
      final patch = {
        'playerProfile': {
          'physical': {
            'heightCm': int.tryParse(_heightController.text.trim()),
            'weightKg': int.tryParse(_weightController.text.trim()),
            'strongFoot': _strongFoot,
          },
          'positions': _csvToList(_positionsController.text),
          'skills': _csvToList(_skillsController.text),
        },
      };

      try {
        await widget.profileController.updateProfilePatch(
          widget.user.uid,
          patch,
          refreshGlobalUser: false,
          alsoUpdateLocalUser: false,
        );
      } on ProfileAccessRevokedException {
        return false;
      }

      if (widget.autoCloseOnSave && showFeedback) {
        Get.back();
      }

      if (showFeedback) {
        Get.snackbar('Succès', 'Profil joueur avancé mis à jour');
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
              value: (_strongFoot == null || _strongFoot!.isEmpty)
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
                labelText: 'Positions (separees par ,)',
                hintText: 'Ex: Ailier droit, MDC, Latéral',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _skillsController,
              decoration: const InputDecoration(
                labelText: 'Compétences (séparées par ,)',
                hintText: 'Ex: Vitesse, Dribble, Finition',
              ),
            ),
            if (widget.showSubmitButton) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : () => save(),
                child: Text(_saving ? 'Sauvegarde...' : 'Sauvegarder'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
