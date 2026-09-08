import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/profile_controller.dart';
import '../../l10n/generated/app_localizations.dart';
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

  /// Les saisons deja archivees, de la plus recente a la plus ancienne.
  late List<SeasonRecord> _history;

  @override
  void initState() {
    super.initState();

    final profile = widget.user.football;
    final season = profile.currentSeason;
    _history = List<SeasonRecord>.of(profile.seasonHistory);

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

  SeasonRecord _currentSeasonFromFields() {
    return SeasonRecord(
      season: _trimOrNull(_seasonController.text),
      competition: _trimOrNull(_competitionController.text),
      ageCategory: _ageCategory,
      appearances: _parsedCount(_appearancesController),
      minutes: _parsedCount(_minutesController),
      goals: _parsedCount(_goalsController),
      assists: _parsedCount(_assistsController),
    );
  }

  bool get _canArchiveCurrentSeason =>
      !_currentSeasonFromFields().isEmpty &&
      _history.length < PlayerFootballProfile.maxSeasonHistory;

  /// Range la saison en cours dans le parcours, et libere les champs.
  ///
  /// Le club et son niveau sont pris sur le profil au moment de l'archivage,
  /// pas demandes au joueur : c'est le seul instant ou l'on sait de source
  /// sure ou il jouait cette saison-la. Le lui faire retaper l'an prochain,
  /// c'est se garantir des clubs mal orthographies dans un dossier qu'on
  /// presente comme qualifie.
  void _archiveCurrentSeason() {
    final profile = widget.user.football;
    final archived = _currentSeasonFromFields().copyWith(
      clubName: profile.currentClubName,
      clubLevel: profile.currentClubLevel,
    );

    setState(() {
      _history = <SeasonRecord>[
        archived,
        ..._history,
      ].take(PlayerFootballProfile.maxSeasonHistory).toList();
      _seasonController.clear();
      _competitionController.clear();
      _appearancesController.clear();
      _minutesController.clear();
      _goalsController.clear();
      _assistsController.clear();
      _ageCategory = null;
    });
    widget.onDirty?.call();
  }

  void _removeArchivedSeason(int index) {
    setState(() => _history = <SeasonRecord>[..._history]..removeAt(index));
    widget.onDirty?.call();
  }

  Map<String, dynamic> buildPatch() {
    final season = _currentSeasonFromFields();

    return <String, dynamic>{
      'openToOpportunities': _openToTrials,
      // Une saison entierement vide est effacee plutot qu'ecrite comme une
      // coquille de champs nuls, qui se lirait comme « renseigne, mais a
      // zero ».
      'currentSeason': season.isEmpty ? null : season.toMap(),
      'seasonHistory': _history
          .map((archived) => archived.toMap())
          .toList(growable: false),
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

    final l10n = AppLocalizations.of(context)!;

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
            l10n.editProfileSaveDeniedTitle,
            l10n.editProfileSaveDeniedMessage,
          );
        }
        return false;
      } catch (_) {
        if (showFeedback) {
          AdFeedback.error(
            l10n.editProfileSaveFailureFallbackTitle,
            l10n.advancedFormStatsSaveFailedMessage,
          );
        }
        return false;
      }

      if (widget.autoCloseOnSave && showFeedback) {
        Get.back();
      }

      if (showFeedback) {
        AdFeedback.success(
          l10n.advancedFormStatsSaveSuccessTitle,
          l10n.advancedFormStatsSaveSuccessMessage,
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
    final l10n = AppLocalizations.of(context)!;

    return Form(
      key: _formKey,
      onChanged: widget.onDirty,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showSectionTitle) ...[
              Text(
                l10n.advancedFormCurrentSeasonTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.advancedFormCurrentSeasonHelper,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],

            TextFormField(
              controller: _seasonController,
              decoration: InputDecoration(
                labelText: l10n.profileSeasonLabel,
                hintText: l10n.advancedFormSeasonHint,
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _competitionController,
              decoration: InputDecoration(
                labelText: l10n.advancedFormCompetitionLabel,
                hintText: l10n.advancedFormCompetitionHint,
              ),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<AgeCategory>(
              initialValue: _ageCategory,
              decoration: InputDecoration(
                labelText: l10n.advancedFormAgeCategoryLabel,
              ),
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

            _countField(_appearancesController, l10n.profileAppearancesLabel),
            const SizedBox(height: 12),
            _countField(_minutesController, l10n.advancedFormMinutesLabel),
            const SizedBox(height: 12),
            _countField(_goalsController, l10n.advancedFormGoalsLabel),
            const SizedBox(height: 12),
            _countField(_assistsController, l10n.profileAssistsLabel),

            const SizedBox(height: 20),
            _buildSeasonHistory(),

            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _openToTrials,
              title: Text(l10n.profileOpenToOpportunitiesLabel),
              subtitle: Text(l10n.advancedFormOpenToTrialsSubtitle),
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
                label: l10n.advancedFormSaveAction,
                onPressed: _saving ? null : () => save(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Le parcours : les saisons deja jouees, et le geste qui y range celle-ci.
  ///
  /// Un recruteur ne juge pas une saison, il juge une trajectoire. Le bouton
  /// porte l'evenement reel -- une saison se termine -- plutot qu'un
  /// formulaire de plus a remplir ligne par ligne.
  Widget _buildSeasonHistory() {
    final l10n = AppLocalizations.of(context)!;
    final maxSeasonHistory = PlayerFootballProfile.maxSeasonHistory;
    final isFull = _history.length >= maxSeasonHistory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.profileHistoryTitle,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          _history.isEmpty
              ? l10n.advancedFormHistoryHelperEmpty
              : (_history.length == 1
                    ? l10n.advancedFormHistorySummaryOne(maxSeasonHistory)
                    : l10n.advancedFormHistorySummaryOther(
                        _history.length,
                        maxSeasonHistory,
                      )),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),

        for (final (index, archived) in _history.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text(_archivedSeasonLabel(archived))),
                IconButton(
                  tooltip: l10n.advancedFormRemoveSeasonTooltip,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => _removeArchivedSeason(index),
                ),
              ],
            ),
          ),

        AdButton(
          leading: Icons.archive_outlined,
          label: l10n.advancedFormArchiveSeasonAction,
          // Desactive plutot que masque : le joueur doit comprendre que le
          // geste existe et pourquoi il ne s'offre pas encore a lui.
          onPressed: _canArchiveCurrentSeason ? _archiveCurrentSeason : null,
        ),
        if (isFull)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.advancedFormHistoryFullMessage,
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// « 2024-25 · Ligue 1 CIV · ASEC Mimosas · 28 matchs, 11 buts »
  String _archivedSeasonLabel(SeasonRecord season) {
    final l10n = AppLocalizations.of(context)!;
    final head = <String>[
      ?season.season,
      ?season.competition,
      ?season.clubName,
    ].join(' · ');

    final figures = <String>[
      if (season.appearances != null)
        l10n.profileSeasonSummaryAppearances(season.appearances!),
      if (season.goals != null) l10n.profileSeasonSummaryGoals(season.goals!),
      if (season.assists != null)
        l10n.profileSeasonSummaryAssists(season.assists!),
    ].join(', ');

    if (head.isEmpty) {
      return figures.isEmpty
          ? l10n.advancedFormArchivedSeasonFallback
          : figures;
    }
    return figures.isEmpty ? head : '$head · $figures';
  }

  Widget _countField(TextEditingController controller, String label) {
    final l10n = AppLocalizations.of(context)!;

    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) return null;

        final parsed = int.tryParse(text);
        if (parsed == null) return l10n.advancedFormInvalidNumberMessage;
        if (parsed < 0) return l10n.advancedFormNegativeValueMessage;
        return null;
      },
    );
  }
}
