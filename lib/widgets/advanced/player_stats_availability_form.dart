import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/profile_controller.dart';
import '../../models/user.dart';

class PlayerStatsAvailabilityForm extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;
  final bool autoCloseOnSave;
  final bool showSubmitButton;
  final bool showSectionTitle;

  const PlayerStatsAvailabilityForm({
    super.key,
    required this.user,
    required this.profileController,
    this.autoCloseOnSave = true,
    this.showSubmitButton = true,
    this.showSectionTitle = true,
  });

  @override
  State<PlayerStatsAvailabilityForm> createState() =>
      PlayerStatsAvailabilityFormState();
}

class PlayerStatsAvailabilityFormState
    extends State<PlayerStatsAvailabilityForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _minutesController;
  late final TextEditingController _goalsController;
  late final TextEditingController _assistsController;
  late final TextEditingController _regionsController;

  bool _openToTrials = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final p = widget.user.playerProfile ?? {};
    final stats = (p['stats'] is Map) ? (p['stats'] as Map) : {};
    final availability =
        (p['availability'] is Map) ? (p['availability'] as Map) : {};

    _minutesController =
        TextEditingController(text: stats['minutes']?.toString() ?? '');
    _goalsController =
        TextEditingController(text: stats['goals']?.toString() ?? '');
    _assistsController =
        TextEditingController(text: stats['assists']?.toString() ?? '');
    _regionsController = TextEditingController(
      text: (availability['regions'] as List?)?.join(', ') ?? '',
    );

    _openToTrials = availability['open'] == true;
  }

  @override
  void dispose() {
    _minutesController.dispose();
    _goalsController.dispose();
    _assistsController.dispose();
    _regionsController.dispose();
    super.dispose();
  }

  List<String> _csvToList(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String? _validateOptionalInt(String? v, {int min = 0, int max = 999999}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) {
      return null;
    }
    final n = int.tryParse(t);
    if (n == null) {
      return 'Nombre invalide';
    }
    if (n < min || n > max) {
      return 'Valeur hors limite';
    }
    return null;
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
          'stats': {
            'minutes': int.tryParse(_minutesController.text.trim()),
            'goals': int.tryParse(_goalsController.text.trim()),
            'assists': int.tryParse(_assistsController.text.trim()),
          },
          'availability': {
            'open': _openToTrials,
            'regions': _csvToList(_regionsController.text),
          },
        }
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
        Get.snackbar('Succès', 'Dossier scout mis à jour');
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
                'Dossier scout - Stats et disponibilité',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _minutesController,
              decoration: const InputDecoration(labelText: 'Minutes jouées'),
              keyboardType: TextInputType.number,
              validator: (v) => _validateOptionalInt(v, min: 0, max: 500000),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _goalsController,
              decoration: const InputDecoration(labelText: 'Buts'),
              keyboardType: TextInputType.number,
              validator: (v) => _validateOptionalInt(v, min: 0, max: 9999),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _assistsController,
              decoration:
                  const InputDecoration(labelText: 'Passes décisives'),
              keyboardType: TextInputType.number,
              validator: (v) => _validateOptionalInt(v, min: 0, max: 9999),
            ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ouvert aux essais / opportunités'),
              value: _openToTrials,
              onChanged: (v) => setState(() => _openToTrials = v),
            ),
            TextFormField(
              controller: _regionsController,
              decoration: const InputDecoration(
                labelText: 'Régions (séparées par ,)',
                hintText: 'Ex: Mali, Sénégal, Côte d\'Ivoire',
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
