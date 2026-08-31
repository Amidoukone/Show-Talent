import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/profile_controller.dart';
import '../../models/football_vocabulary.dart';
import '../../models/org_football_profile.dart';
import '../../models/user.dart';
import '../ad_button.dart';
import '../ad_feedback.dart';

/// Ce qu'un club déclare de lui-même, en listes fermées.
///
/// `structureType` était saisi en toutes lettres et `categories` en CSV : deux
/// champs sur lesquels aucune recherche n'était possible, dans un produit dont
/// c'est la raison d'être.
///
/// Les besoins de recrutement ont disparu de ce formulaire. Ils y étaient
/// saisis en texte (`"CB:high, LB"`) pendant que les offres publiées par le
/// même club portaient déjà la même information, désormais en codes. Deux
/// sources pour un seul fait finissent par se contredire, et c'est l'offre qui
/// est datée, modérée et candidatable — donc c'est elle qui fait foi.
class ClubAdvancedForm extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;
  final bool autoCloseOnSave;
  final bool showSubmitButton;
  final bool showSectionTitle;
  final VoidCallback? onDirty;

  const ClubAdvancedForm({
    super.key,
    required this.user,
    required this.profileController,
    this.autoCloseOnSave = true,
    this.showSubmitButton = true,
    this.showSectionTitle = true,
    this.onDirty,
  });

  @override
  State<ClubAdvancedForm> createState() => ClubAdvancedFormState();
}

class ClubAdvancedFormState extends State<ClubAdvancedForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _federationIdController;
  late List<AgeCategory> _ageCategories;
  ClubLevel? _level;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final profile = widget.user.club;
    _federationIdController = TextEditingController(
      text: profile.federationId ?? '',
    );
    _ageCategories = List<AgeCategory>.of(profile.ageCategories);
    _level = profile.level;
  }

  @override
  void dispose() {
    _federationIdController.dispose();
    super.dispose();
  }

  Map<String, dynamic> buildPatch() {
    return ClubFootballProfile(
      level: _level,
      ageCategories: _ageCategories,
      federationId: _federationIdController.text.trim().isEmpty
          ? null
          : _federationIdController.text.trim(),
    ).toPatch();
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
            'Les informations du club n’ont pas été enregistrées.',
          );
        }
        return false;
      }

      if (widget.autoCloseOnSave && showFeedback) {
        Get.back();
      }

      if (showFeedback) {
        AdFeedback.success(
          'Profil mis à jour',
          'Les informations du club ont été enregistrées.',
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
                'Profil du club',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
            ],

            DropdownButtonFormField<ClubLevel>(
              initialValue: _level,
              decoration: const InputDecoration(
                labelText: 'Niveau de la structure',
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
                setState(() => _level = value);
                widget.onDirty?.call();
              },
            ),
            const SizedBox(height: 20),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Catégories engagées',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AgeCategory.values.map((category) {
                final isSelected = _ageCategories.contains(category);
                return FilterChip(
                  selected: isSelected,
                  label: Text(category.labelFr),
                  onSelected: (_) {
                    setState(() {
                      if (isSelected) {
                        _ageCategories.remove(category);
                      } else {
                        _ageCategories.add(category);
                      }
                    });
                    widget.onDirty?.call();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _federationIdController,
              decoration: const InputDecoration(
                labelText: 'Numéro d’affiliation à la fédération',
                helperText:
                    'C’est ce qui permet de vérifier le club auprès de sa '
                    'fédération.',
                helperMaxLines: 2,
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
