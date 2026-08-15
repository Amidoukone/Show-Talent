import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/profile_controller.dart';
import '../../models/user.dart';
import '../ad_button.dart';
import '../ad_feedback.dart';

class PlayerStatsAvailabilityForm extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;
  final bool autoCloseOnSave;
  final bool showSubmitButton;
  final bool showSectionTitle;
  final VoidCallback? onDirty;

  const PlayerStatsAvailabilityForm({
    super.key,
    required this.user,
    required this.profileController,
    this.autoCloseOnSave = true,
    this.showSubmitButton = true,
    this.showSectionTitle = true,
    this.onDirty,
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
    final availability = (p['availability'] is Map)
        ? (p['availability'] as Map)
        : {};

    _minutesController = TextEditingController(
      text: stats['minutes']?.toString() ?? '',
    );
    _goalsController = TextEditingController(
      text: stats['goals']?.toString() ?? '',
    );
    _assistsController = TextEditingController(
      text: stats['assists']?.toString() ?? '',
    );
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

  bool validate() => _formKey.currentState?.validate() ?? false;

  Map<String, dynamic> buildPatch() {
    return {
      'openToOpportunities': _openToTrials,
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
      },
    };
  }

  Future<bool> save({bool showFeedback = true}) async {
    if (_saving) {
      return false;
    }
    if (!validate()) {
      return false;
    }

    setState(() => _saving = true);
    try {
      final patch = buildPatch();

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
            'Les statistiques et disponibilités n’ont pas été enregistrées.',
          );
        }
        return false;
      }

      if (widget.autoCloseOnSave && showFeedback) {
        Get.back();
      }

      if (showFeedback) {
        AdFeedback.success(
          'Dossier scout mis à jour',
          'Les statistiques et disponibilités ont été enregistrées.',
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
              decoration: const InputDecoration(labelText: 'Passes décisives'),
              keyboardType: TextInputType.number,
              validator: (v) => _validateOptionalInt(v, min: 0, max: 9999),
            ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ouvert aux essais / opportunités'),
              value: _openToTrials,
              onChanged: (v) {
                // Not a FormField, so Form.onChanged never sees this flip on
                // its own -- call onDirty directly or the unsaved-changes
                // guard in the parent screen won't notice this toggle.
                setState(() => _openToTrials = v);
                widget.onDirty?.call();
              },
            ),
            TextFormField(
              controller: _regionsController,
              decoration: const InputDecoration(
                labelText: 'Régions ciblées (séparées par des virgules)',
                hintText: 'Ex : Mali, Sénégal, Côte d’Ivoire',
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
