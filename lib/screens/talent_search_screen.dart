import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/services/users/talent_search_repository.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/utils/country_codes.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:adfoot/widgets/country_picker_sheet.dart';

/// La recherche de talents, telle qu'un recruteur la pose.
///
/// C'est le point d'arrivée de la refonte : le vocabulaire fermé, les champs
/// plats et le `isSearchable` posé par le serveur existent pour que cette
/// question soit posée à Firestore et non au téléphone. Jusqu'ici la recherche
/// hydratait trois cents joueurs sur l'appareil pour filtrer en mémoire — ce
/// qui marchait à onze joueurs et devenait absurde à deux mille.
///
/// Quatre critères, ceux qu'un club pose avant de regarder une vidéo. Chaque
/// critère supplémentaire serait un index composite de plus à déclarer, à
/// déployer et à tenir.
class TalentSearchScreen extends StatefulWidget {
  const TalentSearchScreen({super.key, this.repository});

  /// Injectable pour les tests ; résolu à l'usage sinon.
  final TalentSearchRepository? repository;

  @override
  State<TalentSearchScreen> createState() => _TalentSearchScreenState();
}

class _TalentSearchScreenState extends State<TalentSearchScreen> {
  late final TalentSearchRepository _repository;

  final List<FootballPosition> _positions = <FootballPosition>[];
  String? _nationality;
  int? _bornFrom;
  int? _bornUntil;
  bool _openOnly = false;

  List<AppUser>? _results;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? const TalentSearchRepository();
  }

  TalentSearchQuery get _query => TalentSearchQuery(
    positions: _positions,
    nationality: _nationality,
    bornFrom: _bornFrom,
    bornUntil: _bornUntil,
    openToOpportunitiesOnly: _openOnly,
  );

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await _repository.search(_query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _loading = false;
        // Un index absent renvoie `failed-precondition`, et Firestore repond
        // alors une liste vide plutot qu'une erreur si on ne la dit pas. « Zero
        // resultat » et « la recherche n'a pas pu tourner » ne sont pas la meme
        // information pour un recruteur.
        _error = l10n.talentSearchFailureMessage;
      });
    }
  }

  void _reset() {
    setState(() {
      _positions.clear();
      _nationality = null;
      _bornFrom = null;
      _bornUntil = null;
      _openOnly = false;
      _results = null;
      _error = null;
    });
  }

  Future<void> _pickNationality() async {
    final picked = await showCountryPicker(context);
    if (picked == null) return;
    setState(() => _nationality = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          l10n.talentSearchTitle,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.talentSearchSubtitle,
          style: const TextStyle(fontSize: 12, color: AdColors.onSurfaceMuted),
        ),
        const SizedBox(height: 16),

        _FilterLabel(l10n.profilePositionsLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FootballPosition.values.map((position) {
            final isSelected = _positions.contains(position);
            return FilterChip(
              selected: isSelected,
              label: Text(position.labelFr),
              onSelected: (_) => setState(() {
                if (isSelected) {
                  _positions.remove(position);
                } else {
                  _positions.add(position);
                }
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        _FilterLabel(l10n.talentSearchNationalityLabel),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _nationality == null
                    ? l10n.talentSearchAllNationalities
                    : countryLabel(_nationality),
              ),
            ),
            if (_nationality != null)
              TextButton(
                onPressed: () => setState(() => _nationality = null),
                child: Text(l10n.commonClear),
              ),
            TextButton(
              onPressed: _pickNationality,
              child: Text(l10n.talentSearchChoose),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _FilterLabel(l10n.talentSearchBornBetweenLabel),
        const SizedBox(height: 4),
        Text(
          l10n.talentSearchBornHint,
          style: const TextStyle(fontSize: 12, color: AdColors.onSurfaceMuted),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _YearField(
                label: l10n.talentSearchYearFromLabel,
                value: _bornFrom,
                onChanged: (value) => setState(() => _bornFrom = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _YearField(
                label: l10n.talentSearchYearToLabel,
                value: _bornUntil,
                onChanged: (value) => setState(() => _bornUntil = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _openOnly,
          title: Text(l10n.talentSearchOpenOnlyLabel),
          onChanged: (value) => setState(() => _openOnly = value),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _loading ? null : _run,
                child: Text(
                  _loading
                      ? l10n.talentSearchSearchingButton
                      : l10n.talentSearchSearchButton,
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: _loading ? null : _reset,
              child: Text(l10n.commonReset),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_error != null)
          AdStatePanel.error(
            title: l10n.talentSearchUnavailableTitle,
            message: _error!,
          )
        else if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
        else if (_results != null)
          ..._buildResults(_results!, l10n),
      ],
    );
  }

  List<Widget> _buildResults(List<AppUser> results, AppLocalizations l10n) {
    if (results.isEmpty) {
      return <Widget>[
        AdStatePanel.empty(
          title: l10n.talentSearchNoResultsTitle,
          message: l10n.talentSearchNoResultsMessage,
        ),
      ];
    }

    return <Widget>[
      Text(
        results.length >= TalentSearchRepository.pageSize
            ? l10n.talentSearchResultsCountMany(results.length)
            : (results.length == 1
                  ? l10n.talentSearchResultsCountOne
                  : l10n.talentSearchResultsCountOther(results.length)),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      ...results.map((user) => _TalentResultTile(user: user)),
    ];
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _YearField extends StatefulWidget {
  const _YearField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_YearField> createState() => _YearFieldState();
}

class _YearFieldState extends State<_YearField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: '2006',
      ),
      onChanged: (raw) {
        final parsed = int.tryParse(raw.trim());
        // Une annee hors de ces bornes ne decrit aucun joueur : la transmettre
        // ne renverrait rien, ce qui se lirait comme « aucun joueur » plutot
        // que comme une saisie incomplete.
        if (parsed == null || parsed < 1930 || parsed > 2100) {
          widget.onChanged(null);
          return;
        }
        widget.onChanged(parsed);
      },
    );
  }
}

/// Une fiche de résultat, telle qu'un recruteur la lit en quelques secondes.
class _TalentResultTile extends StatelessWidget {
  const _TalentResultTile({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final football = user.football;

    // L'ordre est celui de la lecture d'un scout : ou il joue, quel age, d'ou
    // il vient, a quel niveau.
    final facts = <String>[
      if (football.positions.isNotEmpty)
        football.positions.map((p) => p.labelFr).join(' · '),
      if (football.birthYear != null) '${football.birthYear}',
      if (football.nationalities.isNotEmpty)
        football.nationalities.map(countryLabel).join(' · '),
      if (football.currentClubLevel != null) football.currentClubLevel!.labelFr,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          user.nom,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          facts.join('  ·  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: user.openToOpportunities == true
            ? const Icon(Icons.how_to_reg_outlined, color: AdColors.success)
            : null,
        onTap: () => Get.to(() => ProfileScreen(uid: user.uid)),
      ),
    );
  }
}
