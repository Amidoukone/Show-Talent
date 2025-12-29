// lib/widgets/advanced/club_advanced_form.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../models/user.dart';
import '../../controller/profile_controller.dart';

class ClubAdvancedForm extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;

  /// true => Get.back() après sauvegarde (bottomSheet)
  /// false => reste dans l’écran (EditAdvancedProfileScreen)
  final bool autoCloseOnSave;

  const ClubAdvancedForm({
    super.key,
    required this.user,
    required this.profileController,
    this.autoCloseOnSave = true,
  });

  @override
  State<ClubAdvancedForm> createState() => _ClubAdvancedFormState();
}

class _ClubAdvancedFormState extends State<ClubAdvancedForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _structureTypeController;
  late final TextEditingController _categoriesController;
  late final TextEditingController _needsController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.user.clubProfile ?? {};

    _structureTypeController =
        TextEditingController(text: c['structureType']?.toString() ?? '');

    _categoriesController = TextEditingController(
      text: (c['categories'] as List?)?.join(', ') ?? '',
    );

    final needs = c['needs'];
    if (needs is List) {
      _needsController = TextEditingController(
        text: needs
            .map((e) {
              if (e is Map) {
                final pos = e['position']?.toString() ?? '';
                final prio = e['priority']?.toString() ?? '';
                return prio.isNotEmpty ? '$pos:$prio' : pos;
              }
              return e.toString();
            })
            .join(', '),
      );
    } else {
      _needsController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _structureTypeController.dispose();
    _categoriesController.dispose();
    _needsController.dispose();
    super.dispose();
  }

  String? _trimOrNull(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  List<String> _csvToList(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<Map<String, String?>> _parseNeeds(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) {
          final parts = e.split(':');
          return {
            'position': parts[0].trim(),
            'priority': parts.length > 1 ? parts[1].trim() : null,
          };
        })
        .toList();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final patch = {
        'clubProfile': {
          'structureType': _trimOrNull(_structureTypeController.text),
          'categories': _csvToList(_categoriesController.text),
          'needs': _parseNeeds(_needsController.text),
        }
      };

      await widget.profileController.updateProfilePatch(
        widget.user.uid,
        patch,
      );

      if (widget.autoCloseOnSave) {
        Get.back();
      }

      Get.snackbar('Succès', 'Profil club avancé mis à jour');
    } finally {
      if (mounted) setState(() => _saving = false);
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
            const Text(
              'Profil club — Avancé',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _structureTypeController,
              decoration: const InputDecoration(
                labelText: 'Type de structure',
                hintText: 'Pro, Semi-pro, Académie…',
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _categoriesController,
              decoration: const InputDecoration(
                labelText: 'Catégories',
                hintText: 'U17, U19, Seniors',
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _needsController,
              decoration: const InputDecoration(
                labelText: 'Besoins',
                hintText: 'Ex: DC:high, BU:medium',
              ),
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Sauvegarde...' : 'Sauvegarder'),
            ),
          ],
        ),
      ),
    );
  }
}
