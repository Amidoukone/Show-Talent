import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/profile_controller.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/org_football_profile.dart';
import '../../models/user.dart';
import '../../utils/country_codes.dart';
import '../ad_button.dart';
import '../ad_feedback.dart';
import '../country_picker_sheet.dart';

/// Ce qu'un agent ou un recruteur déclare de lui-même.
///
/// Le numéro de licence est le seul champ de tout le produit qui soit
/// **vérifiable publiquement** : les fédérations publient les registres de
/// leurs agents licenciés. C'est donc lui qui sépare un agent réel d'un compte
/// qui s'en réclame — et la confiance qu'un joueur peut accorder à la
/// plateforme en dépend plus que de n'importe quel autre champ. Il ne vaut
/// toutefois rien sans la fédération émettrice, sans quoi il ne peut être
/// confronté à aucun registre : les deux vont ensemble.
///
/// Les zones d'intervention passent de « Europe, Afrique » saisi en CSV à des
/// pays en codes ISO. Deux continents ne se croisent avec aucune recherche de
/// joueur, qui raisonne par pays.
class AgentAdvancedForm extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;
  final bool autoCloseOnSave;
  final bool showSubmitButton;
  final bool showSectionTitle;
  final VoidCallback? onDirty;

  const AgentAdvancedForm({
    super.key,
    required this.user,
    required this.profileController,
    this.autoCloseOnSave = true,
    this.showSubmitButton = true,
    this.showSectionTitle = true,
    this.onDirty,
  });

  @override
  State<AgentAdvancedForm> createState() => AgentAdvancedFormState();
}

class AgentAdvancedFormState extends State<AgentAdvancedForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _licenceController;
  late List<String> _countries;
  String? _licenceCountry;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final profile = widget.user.agent;
    _licenceController = TextEditingController(
      text: profile.licenceNumber ?? '',
    );
    _countries = List<String>.of(profile.countries);
    _licenceCountry = profile.licenceCountry;
  }

  @override
  void dispose() {
    _licenceController.dispose();
    super.dispose();
  }

  Map<String, dynamic> buildPatch() {
    return AgentFootballProfile(
      licenceNumber: _licenceController.text.trim().isEmpty
          ? null
          : _licenceController.text.trim(),
      licenceCountry: _licenceCountry,
      countries: _countries,
    ).toPatch();
  }

  bool validate() => _formKey.currentState?.validate() ?? false;

  Future<void> _pickLicenceCountry() async {
    final picked = await showCountryPicker(context);
    if (picked == null) return;

    setState(() => _licenceCountry = picked);
    widget.onDirty?.call();
  }

  Future<void> _addCountry() async {
    final picked = await showCountryPicker(context, excluded: _countries);
    if (picked == null) return;

    setState(() => _countries = <String>[..._countries, picked]);
    widget.onDirty?.call();
  }

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
            l10n.advancedFormAgentSaveFailedMessage,
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
          l10n.advancedFormAgentSaveSuccessMessage,
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
    final isAgent = widget.user.isAgent;

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
                isAgent
                    ? l10n.advancedFormAgentTitle
                    : l10n.advancedFormRecruiterTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextFormField(
              controller: _licenceController,
              decoration: InputDecoration(
                labelText: isAgent
                    ? l10n.advancedFormAgentLicenseLabel
                    : l10n.profileAgentLicenseRefLabel,
                helperText: l10n.advancedFormAgentLicenseHelper,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),

            InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.profileLicenseCountryLabel,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _licenceCountry == null
                          ? l10n.advancedFormNotProvidedLabel
                          : countryLabel(_licenceCountry),
                    ),
                  ),
                  TextButton(
                    onPressed: _pickLicenceCountry,
                    child: Text(l10n.talentSearchChoose),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                isAgent
                    ? l10n.profileAgentCountriesLabel
                    : l10n.profileRecruiterCountriesLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._countries.map(
                  (code) => InputChip(
                    label: Text(countryLabel(code)),
                    onDeleted: () {
                      setState(() {
                        _countries = _countries
                            .where((entry) => entry != code)
                            .toList();
                      });
                      widget.onDirty?.call();
                    },
                  ),
                ),
                if (_countries.length < AgentFootballProfile.maxCountries)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(l10n.advancedFormAddAction),
                    onPressed: _addCountry,
                  ),
              ],
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
}
