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

  @override
  void initState() {
    super.initState();
    final a = widget.user.agentProfile ?? {};

    _licenseController =
        TextEditingController(text: a['licenseNumber']?.toString() ?? '');
    _countryController =
        TextEditingController(text: a['licenseCountry']?.toString() ?? '');
    _zonesController =
        TextEditingController(text: (a['zones'] as List?)?.join(', ') ?? '');
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _countryController.dispose();
    _zonesController.dispose();
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
          refreshGlobalUser: false,
        );
      } on ProfileAccessRevokedException {
        return false;
      }

      if (widget.autoCloseOnSave && showFeedback) {
        Get.back();
      }

      if (showFeedback) {
        Get.snackbar('Succès', 'Profil agent / recruteur avancé mis à jour');
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
                'Profil recruteur / agent avancé',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _licenseController,
              decoration: const InputDecoration(labelText: 'Numéro de licence'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _countryController,
              decoration:
                  const InputDecoration(labelText: 'Pays de la licence'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _zonesController,
              decoration: const InputDecoration(
                labelText: 'Zones (séparées par ,)',
                hintText: 'Ex: Afrique, Europe, Moyen-Orient',
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
