import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/profile_controller.dart';
import '../../models/user.dart';

class ClubAdvancedForm extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;
  final bool autoCloseOnSave;
  final bool showSubmitButton;
  final bool showSectionTitle;

  const ClubAdvancedForm({
    super.key,
    required this.user,
    required this.profileController,
    this.autoCloseOnSave = true,
    this.showSubmitButton = true,
    this.showSectionTitle = true,
  });

  @override
  State<ClubAdvancedForm> createState() => ClubAdvancedFormState();
}

class ClubAdvancedFormState extends State<ClubAdvancedForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _structureTypeController;
  late final TextEditingController _categoriesController;
  late final TextEditingController _needsController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final clubProfile = widget.user.clubProfile ?? {};

    _structureTypeController = TextEditingController(
      text: clubProfile['structureType']?.toString() ?? '',
    );
    _categoriesController = TextEditingController(
      text: (clubProfile['categories'] as List?)?.join(', ') ?? '',
    );

    final needs = clubProfile['needs'];
    if (needs is List) {
      _needsController = TextEditingController(
        text: needs.map((entry) {
          if (entry is Map) {
            final position = entry['position']?.toString() ?? '';
            final priority = entry['priority']?.toString() ?? '';
            return priority.isNotEmpty ? '$position:$priority' : position;
          }
          return entry.toString();
        }).join(', '),
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

  List<Map<String, String?>> _parseNeeds(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((entry) {
          final parts = entry.split(':');
          return {
            'position': parts[0].trim(),
            'priority': parts.length > 1 ? parts[1].trim() : null,
          };
        }).toList();
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
        'clubProfile': {
          'structureType': _trimOrNull(_structureTypeController.text),
          'categories': _csvToList(_categoriesController.text),
          'needs': _parseNeeds(_needsController.text),
        },
      };

      try {
        await widget.profileController.updateProfilePatch(
          widget.user.uid,
          patch,
        );
      } on ProfileAccessRevokedException {
        return false;
      }

      if (widget.autoCloseOnSave && showFeedback) {
        Get.back();
      }

      if (showFeedback) {
        Get.snackbar('Succès', 'Profil club avancé mis à jour');
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
                'Profil club avancé',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _structureTypeController,
              decoration: const InputDecoration(
                labelText: 'Type de structure',
                hintText:
                    'Ex : Club professionnel, centre de formation, académie',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _categoriesController,
              decoration: const InputDecoration(
                labelText: 'Catégories encadrées',
                hintText: 'Ex : U15, U17, U20, Seniors',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _needsController,
              decoration: const InputDecoration(
                labelText: 'Besoins de recrutement prioritaires',
                hintText:
                    'Ex : Défenseur central:haute, avant-centre:moyenne',
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
