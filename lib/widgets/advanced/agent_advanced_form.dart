import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/profile_controller.dart';
import '../../models/user.dart';

class AgentAdvancedForm extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;
  final bool autoCloseOnSave;
  final bool showSubmitButton;
  final bool showSectionTitle;

  const AgentAdvancedForm({
    super.key,
    required this.user,
    required this.profileController,
    this.autoCloseOnSave = true,
    this.showSubmitButton = true,
    this.showSectionTitle = true,
  });

  @override
  State<AgentAdvancedForm> createState() => AgentAdvancedFormState();
}

class AgentAdvancedFormState extends State<AgentAdvancedForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _licenseController;
  late final TextEditingController _countryController;
  late final TextEditingController _zonesController;

  bool _saving = false;

  bool get _isAgent => widget.user.isAgent;

  @override
  void initState() {
    super.initState();
    final profile = widget.user.agentProfile ?? {};

    _licenseController = TextEditingController(
      text: profile['licenseNumber']?.toString() ?? '',
    );
    _countryController = TextEditingController(
      text: profile['licenseCountry']?.toString() ?? '',
    );
    _zonesController = TextEditingController(
      text: (profile['zones'] as List?)?.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _countryController.dispose();
    _zonesController.dispose();
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
      final patch = {
        'agentProfile': {
          'licenseNumber': _trimOrNull(_licenseController.text),
          'licenseCountry': _trimOrNull(_countryController.text),
          'zones': _csvToList(_zonesController.text),
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
        Get.snackbar(
          'Succès',
          _isAgent
              ? 'Profil agent avancé mis à jour'
              : 'Profil recruteur avancé mis à jour',
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showSectionTitle) ...[
              Text(
                _isAgent ? 'Profil agent avancé' : 'Profil recruteur avancé',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _licenseController,
              decoration: InputDecoration(
                labelText: _isAgent
                    ? 'Numéro de licence'
                    : 'Référence de licence ou d’agrément',
                hintText: _isAgent
                    ? 'Ex : LIC-FAF-2026-014'
                    : 'Ex : AGR-RECRUT-2026-03',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _countryController,
              decoration: InputDecoration(
                labelText: _isAgent
                    ? 'Pays de délivrance de la licence'
                    : 'Pays de délivrance',
                hintText: 'Ex : Côte d’Ivoire',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _zonesController,
              decoration: InputDecoration(
                labelText: _isAgent
                    ? 'Zones de représentation'
                    : 'Zones d’intervention',
                hintText: _isAgent
                    ? 'Ex : Afrique de l’Ouest, France, Belgique'
                    : 'Ex : Côte d’Ivoire, Mali, Sénégal',
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
