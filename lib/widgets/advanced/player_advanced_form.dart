import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/profile_controller.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/football_vocabulary.dart';
import '../../models/player_football_profile.dart';
import '../../models/user.dart';
import '../../utils/country_codes.dart';
import '../ad_button.dart';
import '../country_picker_sheet.dart';
import '../ad_feedback.dart';

/// L'identité footballistique du joueur, en listes fermées.
///
/// Remplace le formulaire en texte libre : postes en CSV, « qualités clés »
/// auto-déclarées, taille et poids enfouis dans une map. Ce qu'un recruteur
/// filtre doit être choisi, pas tapé — sinon « Défense », « défenseur central »
/// et « CB » désignent le même joueur sans jamais se rencontrer dans une
/// requête.
///
/// Les qualités clés ont disparu et ne reviendront pas : « rapide », « bon
/// dribbleur » saisis par le joueur lui-même n'ont aucune valeur pour un scout
/// et affaiblissent le reste de la fiche. Ce qui relève du jugement se regarde
/// sur la vidéo.
///
/// L'API publique est inchangée — [PlayerAdvancedFormState.buildPatch],
/// [PlayerAdvancedFormState.validate], [PlayerAdvancedFormState.save] — parce
/// que `edit_advanced_profile_screen.dart` fusionne ce patch avec celui du
/// formulaire de saison et n'a pas à connaître leur contenu.
class PlayerAdvancedForm extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;
  final bool autoCloseOnSave;
  final bool showSubmitButton;
  final bool showSectionTitle;
  final VoidCallback? onDirty;

  const PlayerAdvancedForm({
    super.key,
    required this.user,
    required this.profileController,
    this.autoCloseOnSave = true,
    this.showSubmitButton = true,
    this.showSectionTitle = true,
    this.onDirty,
  });

  @override
  State<PlayerAdvancedForm> createState() => PlayerAdvancedFormState();
}

class PlayerAdvancedFormState extends State<PlayerAdvancedForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _clubNameController;

  late List<FootballPosition> _positions;
  late List<String> _nationalities;
  StrongFoot? _strongFoot;
  ContractStatus? _contractStatus;
  DateTime? _contractEndDate;
  ClubLevel? _clubLevel;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final profile = widget.user.football;

    _heightController = TextEditingController(
      text: profile.heightCm?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: profile.weightKg?.toString() ?? '',
    );
    _clubNameController = TextEditingController(
      text: profile.currentClubName ?? widget.user.clubActuel ?? '',
    );

    _positions = List<FootballPosition>.of(profile.positions);
    _nationalities = List<String>.of(profile.nationalities);
    _strongFoot = profile.strongFoot;
    _contractStatus = profile.contractStatus;
    _contractEndDate = profile.contractEndDate;
    _clubLevel = profile.currentClubLevel;
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _clubNameController.dispose();
    super.dispose();
  }

  void _markDirty() {
    widget.onDirty?.call();
  }

  /// Ajoute ou retire un poste, en conservant l'ordre de sélection.
  ///
  /// L'ordre est l'information : le premier poste coché est le poste
  /// principal, et c'est celui qu'un recruteur lit en premier.
  void _togglePosition(FootballPosition position) {
    setState(() {
      if (_positions.contains(position)) {
        _positions.remove(position);
      } else if (_positions.length < FootballPosition.maxPerPlayer) {
        _positions.add(position);
      }
    });
    _markDirty();
  }

  /// Sans poste, la fiche n'est pas « moins complete » : elle est absente.
  ///
  /// `TalentSearchRepository` filtre `positionCodes` en `arrayContainsAny`, et
  /// `computeIsSearchable` refuse `isSearchable` sans lui -- donc la fiche ne
  /// passe meme pas le premier `where` de la requete. Le message dit la
  /// consequence, pas l'injonction : « renseignez ce champ » ne dit pas
  /// pourquoi, et un joueur qui ne sait pas pourquoi remplit mal ou pas.
  String? _validatePositions(List<FootballPosition>? positions) {
    if (positions == null || positions.isEmpty) {
      return AppLocalizations.of(
        context,
      )!.advancedFormPositionsRequiredValidator;
    }
    return null;
  }

  /// Meme enjeu, meme formulation.
  String? _validateNationalities(List<String>? nationalities) {
    if (nationalities == null || nationalities.isEmpty) {
      return AppLocalizations.of(
        context,
      )!.advancedFormNationalitiesRequiredValidator;
    }
    return null;
  }

  int? _parsedInt(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  PlayerFootballProfile _currentProfile() {
    return PlayerFootballProfile(
      nationalities: _nationalities,
      positions: _positions,
      strongFoot: _strongFoot,
      heightCm: _parsedInt(_heightController),
      weightKg: _parsedInt(_weightController),
      contractStatus: _contractStatus,
      contractEndDate: _contractEndDate,
      currentClubName: _clubNameController.text.trim().isEmpty
          ? null
          : _clubNameController.text.trim(),
      currentClubLevel: _clubLevel,
    );
  }

  Map<String, dynamic> buildPatch() {
    // Le miroir vers `clubActuel` a disparu avec la raison qui le justifiait :
    // toutes les surfaces lisent maintenant `currentClubName` en premier. Il
    // ne recopiait le club que pour une seule des deux sources concurrentes,
    // et l'en-tete, qui preferait `team`, continuait d'afficher l'ancien club.
    return _currentProfile().toPatch();
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
            l10n.advancedFormPlayerSaveFailedMessage,
          );
        }
        return false;
      }

      if (widget.autoCloseOnSave && showFeedback) {
        Get.back();
      }

      if (showFeedback) {
        AdFeedback.success(
          l10n.advancedFormSaveSuccessTitle,
          l10n.advancedFormPlayerSaveSuccessMessage,
        );
      }

      return true;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickContractEndDate() async {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _contractEndDate ?? DateTime(now.year + 1, 6, 30),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      helpText: l10n.profileContractEndLabel,
    );
    if (picked == null) return;

    setState(() => _contractEndDate = picked);
    _markDirty();
  }

  Future<void> _addNationality() async {
    final picked = await showCountryPicker(context, excluded: _nationalities);
    if (picked == null) return;

    setState(() => _nationalities = <String>[..._nationalities, picked]);
    _markDirty();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final expectsEndDate = _contractStatus?.expectsEndDate == true;

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
                l10n.editProfileHeaderTitlePlayer,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
            ],

            _label(l10n.advancedFormPositionsRequiredLabel),
            Text(
              l10n.advancedFormPositionsHelper,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            // Un `FormField` plutot qu'un simple selecteur : le poste decide
            // que cette fiche existe ou non pour un recruteur, et il etait
            // jusqu'ici hors du `Form`, donc jamais valide. Un joueur pouvait
            // remplir sa taille, son pied fort, ses statistiques, enregistrer,
            // lire « Profil avance » -- et n'apparaitre dans aucune recherche.
            //
            // Meme correction que pour l'offre (c80719c) et l'evenement : le
            // champ dont depend la trouvabilite est valide par le meme
            // `validate()` que le reste, et l'erreur se pose sous les puces.
            FormField<List<FootballPosition>>(
              initialValue: _positions,
              validator: _validatePositions,
              builder: (state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PositionSelector(
                      selected: _positions,
                      onToggle: (position) {
                        _togglePosition(position);
                        state.didChange(_positions);
                      },
                    ),
                    if (state.hasError) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.errorText!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<StrongFoot>(
              initialValue: _strongFoot,
              decoration: InputDecoration(
                labelText: l10n.profileStrongFootLabel,
              ),
              items: StrongFoot.values
                  .map(
                    (foot) => DropdownMenuItem<StrongFoot>(
                      value: foot,
                      child: Text(foot.labelFr),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => _strongFoot = value);
                _markDirty();
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _heightController,
              decoration: InputDecoration(
                labelText: l10n.advancedFormHeightFieldLabel,
              ),
              keyboardType: TextInputType.number,
              validator: (value) => _validateBounded(
                value,
                PlayerFootballProfile.minHeightCm,
                PlayerFootballProfile.maxHeightCm,
                l10n.profileHeightLabel,
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _weightController,
              decoration: InputDecoration(
                labelText: l10n.advancedFormWeightFieldLabel,
              ),
              keyboardType: TextInputType.number,
              validator: (value) => _validateBounded(
                value,
                PlayerFootballProfile.minWeightKg,
                PlayerFootballProfile.maxWeightKg,
                l10n.profileWeightLabel,
              ),
            ),
            const SizedBox(height: 20),

            _label(l10n.advancedFormNationalitiesRequiredLabel),
            Text(
              l10n.advancedFormNationalitiesHelper,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            // Meme raison que les postes : `computeIsSearchable` exige au
            // moins une nationalite, donc son absence rend la fiche
            // introuvable et non simplement incomplete.
            FormField<List<String>>(
              initialValue: _nationalities,
              validator: _validateNationalities,
              builder: (state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NationalityList(
                      codes: _nationalities,
                      canAdd:
                          _nationalities.length <
                          PlayerFootballProfile.maxNationalities,
                      onRemove: (code) {
                        setState(() {
                          _nationalities = _nationalities
                              .where((entry) => entry != code)
                              .toList();
                        });
                        _markDirty();
                        state.didChange(_nationalities);
                      },
                      onAdd: () async {
                        await _addNationality();
                        state.didChange(_nationalities);
                      },
                    ),
                    if (state.hasError) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.errorText!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            _label(l10n.advancedFormSituationLabel),
            const SizedBox(height: 8),
            TextFormField(
              controller: _clubNameController,
              decoration: InputDecoration(
                labelText: l10n.profileCurrentClubLabel,
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<ClubLevel>(
              initialValue: _clubLevel,
              decoration: InputDecoration(
                labelText: l10n.advancedFormClubLevelFieldLabel,
              ),
              items: ClubLevel.values
                  .map(
                    (level) => DropdownMenuItem<ClubLevel>(
                      value: level,
                      child: Text(level.labelFr),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => _clubLevel = value);
                _markDirty();
              },
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<ContractStatus>(
              initialValue: _contractStatus,
              decoration: InputDecoration(
                labelText: l10n.advancedFormContractStatusLabel,
              ),
              items: ContractStatus.values
                  .map(
                    (status) => DropdownMenuItem<ContractStatus>(
                      value: status,
                      child: Text(status.labelFr),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _contractStatus = value;
                  // Une date de fin n'a plus de sens si le joueur devient
                  // libre : la laisser afficherait un engagement qui n'existe
                  // pas.
                  if (value?.expectsEndDate != true) {
                    _contractEndDate = null;
                  }
                });
                _markDirty();
              },
            ),

            if (expectsEndDate) ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.profileContractEndLabel,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _contractEndDate == null
                            ? l10n.advancedFormNotProvidedLabel
                            : '${_contractEndDate!.day.toString().padLeft(2, '0')}/'
                                  '${_contractEndDate!.month.toString().padLeft(2, '0')}/'
                                  '${_contractEndDate!.year}',
                      ),
                    ),
                    TextButton(
                      onPressed: _pickContractEndDate,
                      child: Text(l10n.talentSearchChoose),
                    ),
                  ],
                ),
              ),
            ],

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

  Widget _label(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
  );

  String? _validateBounded(String? value, int min, int max, String label) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;

    final parsed = int.tryParse(text);
    if (parsed == null) {
      return AppLocalizations.of(context)!.advancedFormInvalidNumberMessage;
    }
    if (parsed < min || parsed > max) {
      return AppLocalizations.of(
        context,
      )!.advancedFormBoundedInvalidMessage(label);
    }
    return null;
  }
}

/// Les dix postes, en cases à cocher.
class _PositionSelector extends StatelessWidget {
  const _PositionSelector({required this.selected, required this.onToggle});

  final List<FootballPosition> selected;
  final ValueChanged<FootballPosition> onToggle;

  @override
  Widget build(BuildContext context) {
    final atLimit = selected.length >= FootballPosition.maxPerPlayer;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: FootballPosition.values.map((position) {
        final index = selected.indexOf(position);
        final isSelected = index >= 0;

        return FilterChip(
          selected: isSelected,
          // Un poste non coché devient indisponible une fois la limite
          // atteinte, au lieu d'accepter le clic puis de l'ignorer en
          // silence.
          onSelected: (!isSelected && atLimit)
              ? null
              : (_) => onToggle(position),
          label: Text(
            isSelected ? '${index + 1}. ${position.labelFr}' : position.labelFr,
          ),
        );
      }).toList(),
    );
  }
}

/// Les nationalités retenues, et le bouton pour en ajouter une.
class _NationalityList extends StatelessWidget {
  const _NationalityList({
    required this.codes,
    required this.canAdd,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> codes;
  final bool canAdd;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...codes.map(
          (code) => InputChip(
            label: Text(countryLabel(code)),
            onDeleted: () => onRemove(code),
          ),
        ),
        if (canAdd)
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: Text(l10n.advancedFormAddAction),
            onPressed: onAdd,
          ),
      ],
    );
  }
}
