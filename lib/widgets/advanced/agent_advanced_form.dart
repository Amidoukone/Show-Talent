// lib/widgets/advanced/agent_advanced_form.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../models/user.dart';
import '../../controller/profile_controller.dart';

class AgentAdvancedForm extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;

  /// true => Get.back() après sauvegarde (bottomSheet)
  /// false => reste dans l’écran (EditAdvancedProfileScreen)
  final bool autoCloseOnSave;

  const AgentAdvancedForm({
    super.key,
    required this.user,
    required this.profileController,
    this.autoCloseOnSave = true,
  });

  @override
  State<AgentAdvancedForm> createState() => _AgentAdvancedFormState();
}

class _AgentAdvancedFormState extends State<AgentAdvancedForm> {
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

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final patch = {
        'agentProfile': {
          'licenseNumber': _trimOrNull(_licenseController.text),
          'licenseCountry': _trimOrNull(_countryController.text),
          'zones': _csvToList(_zonesController.text),
        },
      };

      await widget.profileController.updateProfilePatch(
        widget.user.uid,
        patch,
      );

      if (widget.autoCloseOnSave) {
        Get.back();
      }

      Get.snackbar('Succès', 'Profil agent / recruteur avancé mis à jour');
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
              'Profil recruteur / agent — Avancé',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _licenseController,
              decoration: const InputDecoration(labelText: 'Numéro de licence'),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _countryController,
              decoration: const InputDecoration(labelText: 'Pays de la licence'),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _zonesController,
              decoration: const InputDecoration(
                labelText: 'Zones (séparées par ,)',
                hintText: 'Ex: Afrique, Europe, Moyen-Orient',
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
