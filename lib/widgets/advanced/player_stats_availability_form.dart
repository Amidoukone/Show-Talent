import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/profile_controller.dart';
import '../../models/football_vocabulary.dart';
import '../../models/player_football_profile.dart';
import '../../models/user.dart';
import '../ad_button.dart';
import '../ad_feedback.dart';

/// La saison en cours, et la disponibilité.
///
/// Les statistiques vivaient sans contexte : « 900 minutes, 4 buts » ne dit
/// rien tant qu'on ignore en quelle saison, dans quel championnat et dans
/// quelle catégorie d'âge. Un recruteur ne peut rien faire d'un chiffre nu, et
/// une fiche qui l'oblige à demander est une fiche qu'il repose.
///
/// Une seule saison, volontairement. Un historique complet est un autre
/// chantier, et une fiche qui empile cinq saisons n'est plus lue en vingt
/// secondes.
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

  late final TextEditingController _seasonController;
  late final TextEditingController _competitionController;
  late final TextEditingController _appearancesController;
  late final TextEditingController _minutesController;
  late final TextEditingController _goalsController;
  late final TextEditingController _assistsController;

  AgeCategory? _ageCategory;
  bool _openToTrials = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final profile = widget.user.football;
    final season = profile.currentSeason;

    _seasonController = TextEditingController(text: season?.season ?? '');
    _competitionController = TextEditingController(
      text: season?.competition ?? '',
    );
    _appearancesController = TextEditingController(
      text: season?.appearances?.toString() ?? '',
    );
    _minutesController = TextEditingController(
      text: season?.minutes?.toString() ?? '',
    );
    _goalsController = TextEditingController(
      text: season?.goals?.toString() ?? '',
    );
    _assistsController = TextEditingController(
      text: season?.assists?.toString() ?? '',
    );

    _ageCategory = season?.ageCategory;
    _openToTrials = widget.user.openToOpportunities == true;
  }

  @override
  void dispose() {
    _seasonController.dispose();
    _competitionController.dispose();
    _appearancesController.dispose();
    _minutesController.dispose();
    _goalsController.dispose();
    _assistsController.dispose();
    super.dispose();
  }

  int? _parsedCount(TextEditingController controller) {
    final parsed = int.tryParse(controller.text.trim());
    return (parsed == null || parsed < 0) ? null : parsed;
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, dynamic> buildPatch() {
    final season = SeasonRecord(
      season: _trimOrNull(_seasonController.text),
      competition: _trimOrNull(_competitionController.text),
      ageCategory: _ageCategory,
      appearances: _parsedCount(_appearancesController),
      minutes: _parsedCount(_minutesController),
      goals: _parsedCount(_goalsController),
      assists: _parsedCount(_assistsController),
    );

    return <String, dynamic>{
      'openToOpportunities': _openToTrials,
      // Une saison entierement vide est effacee plutot qu'ecrite comme une
      // coquille de champs nuls, qui se lirait comme « renseigne, mais a
      // zero ».
      'currentSeason': season.isEmpty ? null : season.toMap(),
    };
  }

  bool validate() => _formKey.currentState?.validate() ?? false;

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
            'Le dossier scout n’a pas été enregistré.',
          );
        }
        return false;
      }

      if (widget.autoCloseOnSave && showFeedback) {
        Get.back();
      }

      if (showFeedback) {
        AdFeedback.success(
          'Dossier mis à jour',
          'Le dossier scout a été enregistré.',
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
                'Saison en cours',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Des chiffres sans saison ni compétition ne veulent rien dire '
                'pour un recruteur.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],

            TextFormField(
              controller: _seasonController,
              decoration: const InputDecoration(
                labelText: 'Saison',
                hintText: '2025-26',
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _competitionController,
              decoration: const InputDecoration(
                labelText: 'Compétition',
                hintText: 'Ligue 1 CIV, Coupe nationale...',
              ),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<AgeCategory>(
              initialValue: _ageCategory,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: AgeCategory.values
                  .map(
                    (category) => DropdownMenuItem<AgeCategory>(
                      value: category,
                      child: Text(category.labelFr),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => _ageCategory = value);
                widget.onDirty?.call();
              },
            ),
            const SizedBox(height: 12),

            _countField(_appearancesController, 'Matchs joués'),
            const SizedBox(height: 12),
            _countField(_minutesController, 'Minutes jouées'),
            const SizedBox(height: 12),
            _countField(_goalsController, 'Buts'),
            const SizedBox(height: 12),
            _countField(_assistsController, 'Passes décisives'),

            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _openToTrials,
              title: const Text('Ouvert aux opportunités'),
              subtitle: const Text(
                'Visible par les clubs et les recruteurs.',
              ),
              onChanged: (value) {
                setState(() => _openToTrials = value);
                widget.onDirty?.call();
              },
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

  Widget _countField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) return null;

        final parsed = int.tryParse(text);
        if (parsed == null) return 'Nombre invalide';
        if (parsed < 0) return 'Valeur négative';
        return null;
      },
    );
  }
}
