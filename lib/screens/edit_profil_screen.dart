import 'dart:io';

import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/controller/profile_controller.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_profile_cards.dart';
import 'package:adfoot/widgets/profile_action_notice.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/user.dart';
import 'package:adfoot/services/app_logger.dart';

class EditProfileScreen extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;

  const EditProfileScreen({
    super.key,
    required this.user,
    required this.profileController,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const kPrimary = AdColors.brand;
  static const kSurface = AdColors.surface;

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nomController;
  late final TextEditingController _bioController;
  late final TextEditingController _phoneController;
  late final TextEditingController _languagesController;
  late final TextEditingController _cityController;
  late final TextEditingController _regionController;
  late final TextEditingController _countryController;
  late final TextEditingController _positionController;
  late final TextEditingController _teamController;
  late final TextEditingController _ligueController;
  late final TextEditingController _entrepriseController;
  late final TextEditingController _nombreRecrutementsController;

  DateTime? _selectedBirthDate;
  bool _saving = false;
  bool _isDirty = false;
  String? _saveFailureTitle;
  String? _saveFailureMessage;

  AppUser get user {
    final liveUser = profileController.user;
    if (liveUser != null && liveUser.uid == widget.user.uid) {
      return liveUser;
    }
    return widget.user;
  }

  ProfileController get profileController => widget.profileController;

  bool get _isPlayer => user.isPlayer || user.isCoach;

  /// Le coach, distingue du joueur : il garde un poste en texte libre la ou le
  /// joueur passe par la liste fermee. Voir la construction de la patch.
  bool get _isCoach => user.isCoach;
  bool get _isClub => user.role == 'club';
  bool get _isRecruiter => user.isRecruiter;

  @override
  void initState() {
    super.initState();
    _nomController = TextEditingController(text: user.nom);
    _bioController = TextEditingController(text: user.bio ?? '');
    _phoneController = TextEditingController(text: user.phone ?? '');
    _languagesController = TextEditingController(
      text: user.languages?.join(', ') ?? '',
    );
    _cityController = TextEditingController(text: user.city ?? '');
    _regionController = TextEditingController(text: user.region ?? '');
    _countryController = TextEditingController(text: user.country ?? '');
    _positionController = TextEditingController(text: user.position ?? '');
    // Le club type, avec les deux anciens champs en secours tant que des
    // comptes crees avant la bascule n'ont que ceux-la. Le premier
    // enregistrement les convertit, puisque la patch n'ecrit plus que
    // `currentClubName`.
    _teamController = TextEditingController(
      text: user.football.currentClubName ?? user.team ?? user.clubActuel ?? '',
    );
    _ligueController = TextEditingController(text: user.ligue ?? '');
    _entrepriseController = TextEditingController(text: user.entreprise ?? '');
    _nombreRecrutementsController = TextEditingController(
      text: user.nombreDeRecrutements?.toString() ?? '',
    );
    _selectedBirthDate = user.birthDate;
  }

  @override
  void dispose() {
    _nomController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _languagesController.dispose();
    _cityController.dispose();
    _regionController.dispose();
    _countryController.dispose();
    _positionController.dispose();
    _teamController.dispose();
    _ligueController.dispose();
    _entrepriseController.dispose();
    _nombreRecrutementsController.dispose();
    super.dispose();
  }

  String _trimOrEmpty(String value) => value.trim();

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _putNullableStringPatch(
    Map<String, dynamic> patch,
    String key,
    String value,
    String? currentValue,
  ) {
    final normalized = _trimOrNull(value);
    if (normalized != null) {
      patch[key] = normalized;
    } else if ((currentValue?.trim().isNotEmpty ?? false)) {
      patch[key] = ProfileController.deleteField;
    }
  }

  int? _intOrNull(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }

  int? _intOrNullClamped(String value, {int? min, int? max}) {
    final parsed = _intOrNull(value);
    if (parsed == null) {
      return null;
    }
    int clamped = parsed;
    if (min != null && clamped < min) {
      clamped = min;
    }
    if (max != null && clamped > max) {
      clamped = max;
    }
    return clamped;
  }

  String? _validateOptionalNonNegativeInt(
    AppLocalizations l10n,
    String? value, {
    int max = 9999,
  }) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final number = int.tryParse(text);
    if (number == null) {
      return l10n.editProfileInvalidNumberValidator;
    }
    if (number < 0) {
      return l10n.editProfilePositiveNumberValidator;
    }
    if (number > max) {
      return l10n.editProfileMaxValueValidator(max);
    }
    return null;
  }

  InputDecorationThemeData _inputDecorationTheme(BuildContext context) {
    final base = Theme.of(context).inputDecorationTheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AdColors.borderMuted),
    );
    final focused = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kPrimary, width: 1.6),
    );

    return base.copyWith(
      filled: true,
      fillColor: AdColors.surfaceCard,
      border: border,
      enabledBorder: border,
      focusedBorder: focused,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(color: AdColors.onSurfaceMuted),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: kPrimary),
      ),
    );
  }

  /// La date de naissance, exigee des joueurs et d'eux seuls.
  ///
  /// `computeIsSearchable` refuse `isSearchable` sans `birthYear`, qui en est
  /// derive : un joueur sans date de naissance n'apparait dans aucune
  /// recherche de recruteur, et rien ne le lui disait -- le champ etait
  /// facultatif et le restait sans consequence visible.
  ///
  /// Le role strict, et non `_isPlayer` qui englobe le coach : un coach n'est
  /// jamais cherchable (la regle exige `role == "joueur"`), donc lui reclamer
  /// sa date de naissance serait une exigence sans contrepartie.
  Widget _buildBirthDateField(BuildContext context, AppLocalizations l10n) {
    return FormField<DateTime>(
      initialValue: _selectedBirthDate,
      validator: (_) {
        if (!user.isPlayer) return null;
        if (_selectedBirthDate != null) return null;
        return l10n.editProfileBirthDateRequiredValidator;
      },
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBirthDateInput(context, l10n, state),
          if (state.hasError) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                state.errorText!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBirthDateInput(
    BuildContext context,
    AppLocalizations l10n,
    FormFieldState<DateTime> state,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await _pickBirthDate(l10n);
        state.didChange(_selectedBirthDate);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: user.isPlayer
              ? l10n.editProfileBirthDateRequiredLabel
              : l10n.editProfileBirthDateLabel,
          prefixIcon: const Icon(Icons.cake_outlined, color: kPrimary),
          suffixIcon: _selectedBirthDate != null
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    setState(() => _selectedBirthDate = null);
                    state.didChange(null);
                  },
                  tooltip: l10n.commonClear,
                )
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedBirthDate != null
                    ? _formatBirthDate(_selectedBirthDate!)
                    : l10n.editProfileBirthDatePlaceholder,
                style: TextStyle(
                  color: _selectedBirthDate != null
                      ? AdColors.onSurface
                      : AdColors.onSurfaceMuted,
                  fontWeight: _selectedBirthDate != null
                      ? FontWeight.w600
                      : null,
                ),
              ),
            ),
            const Icon(Icons.edit_calendar_outlined, color: kPrimary),
          ],
        ),
      ),
    );
  }

  String _formatBirthDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> _pickBirthDate(AppLocalizations l10n) async {
    final now = DateTime.now();
    final initial =
        _selectedBirthDate ?? DateTime(now.year - 18, now.month, now.day);
    final earliest = DateTime(now.year - 60);
    final latest = DateTime(now.year - 10, now.month, now.day);

    DateTime initialDate = initial;
    if (initialDate.isAfter(latest)) {
      initialDate = latest;
    }
    if (initialDate.isBefore(earliest)) {
      initialDate = earliest;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: earliest,
      lastDate: latest,
      helpText: l10n.editProfileBirthDatePickerHelpText,
      confirmText: l10n.newPasswordSubmit,
      cancelText: l10n.commonCancel,
    );

    if (picked != null) {
      setState(() => _selectedBirthDate = picked);
    }
  }

  Future<void> _handleBackNavigation({Object? result}) async {
    if (!_isDirty) {
      if (mounted) Navigator.of(context).pop(result);
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final shouldDiscard = await AdDialogs.confirm(
      context: context,
      title: l10n.editProfileDiscardConfirmTitle,
      message: l10n.editProfileDiscardConfirmMessage,
      confirmLabel: l10n.editProfileDiscardAction,
      cancelLabel: l10n.eventFormContinueEditingAction,
      danger: true,
    );
    if (shouldDiscard && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _saving = true;
      _saveFailureTitle = null;
      _saveFailureMessage = null;
    });

    try {
      final patch = <String, dynamic>{};

      patch['nom'] = _trimOrEmpty(_nomController.text);

      final phone = _trimOrNull(_phoneController.text);
      if (phone != null) {
        patch['phone'] = phone;
      } else if ((user.phone?.isNotEmpty ?? false)) {
        patch['phone'] = ProfileController.deleteField;
      }

      final languages = _languagesController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (languages.isNotEmpty) {
        patch['languages'] = languages;
      } else if (user.languages?.isNotEmpty == true) {
        patch['languages'] = ProfileController.deleteField;
      }

      final bio = _trimOrNull(_bioController.text);
      if (bio != null) {
        patch['bio'] = bio;
      } else if ((user.bio?.isNotEmpty ?? false)) {
        patch['bio'] = ProfileController.deleteField;
      }

      _putNullableStringPatch(patch, 'city', _cityController.text, user.city);
      _putNullableStringPatch(
        patch,
        'region',
        _regionController.text,
        user.region,
      );
      _putNullableStringPatch(
        patch,
        'country',
        _countryController.text,
        user.country,
      );

      if (_isPlayer) {
        if (_selectedBirthDate != null) {
          patch['birthDate'] = _selectedBirthDate;
        } else if (user.birthDate != null) {
          patch['birthDate'] = ProfileController.deleteField;
        }

        // Le poste en texte libre ne survit que pour le coach.
        //
        // « Ailier droit » tape a la main ne se filtre pas : la recherche
        // interroge `positionCodes`, la liste fermee que le joueur coche dans
        // le formulaire avance. Garder les deux, c'etait afficher le texte
        // libre sur la fiche pendant qu'un recruteur filtrait sur l'autre --
        // un joueur pouvait lire « Milieu axial » sur son profil et
        // n'apparaitre dans aucune recherche de milieu.
        //
        // Le coach, lui, n'a pas de poste de terrain : « Fonction sportive »
        // (coach principal, preparateur physique) n'a aucun equivalent dans
        // la liste fermee, et lui retirer le champ le laisserait sans rien.
        if (_isCoach) {
          final position = _trimOrNull(_positionController.text);
          if (position != null) {
            patch['position'] = position;
          } else if ((user.position?.isNotEmpty ?? false)) {
            patch['position'] = ProfileController.deleteField;
          }
        }

        // Un seul club, celui que la fiche affiche et que le portail admin
        // corrige. `team` et `clubActuel` portaient le meme fait sans jamais
        // etre ecrits ensemble par les trois surfaces qui y touchaient.
        final club = _trimOrNull(_teamController.text);
        if (club != null) {
          patch['currentClubName'] = club;
        } else if ((user.football.currentClubName?.isNotEmpty ?? false)) {
          patch['currentClubName'] = ProfileController.deleteField;
        }
      }

      if (_isClub) {
        patch['nomClub'] = _trimOrEmpty(_nomController.text);

        final ligue = _trimOrNull(_ligueController.text);
        if (ligue != null) {
          patch['ligue'] = ligue;
        } else if ((user.ligue?.isNotEmpty ?? false)) {
          patch['ligue'] = ProfileController.deleteField;
        }
      }

      if (_isRecruiter) {
        final entreprise = _trimOrNull(_entrepriseController.text);
        if (entreprise != null) {
          patch['entreprise'] = entreprise;
        } else if ((user.entreprise?.isNotEmpty ?? false)) {
          patch['entreprise'] = ProfileController.deleteField;
        }

        final recruitments = _intOrNullClamped(
          _nombreRecrutementsController.text,
          min: 0,
          max: 9999,
        );
        if (recruitments != null) {
          patch['nombreDeRecrutements'] = recruitments;
        } else if (user.nombreDeRecrutements != null) {
          patch['nombreDeRecrutements'] = ProfileController.deleteField;
        }
      }

      await profileController.updateProfilePatch(user.uid, patch);

      AdFeedback.success(
        l10n.editProfileSaveSuccessTitle,
        l10n.editProfileSaveSuccessMessage,
      );
      _isDirty = false;
      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } on ProfileAccessRevokedException catch (e) {
      final title =
          e.title ??
          profileController.lastProfileWriteErrorTitle ??
          l10n.editProfileSaveDeniedTitle;
      final message =
          e.message ??
          profileController.lastProfileWriteErrorMessage ??
          l10n.editProfileSaveDeniedMessage;
      if (mounted) {
        setState(() {
          _saveFailureTitle = title;
          _saveFailureMessage = message;
        });
      }
      return;
    } catch (e) {
      AppLogger.debug('EditProfile _save error: $e');
      if (mounted) {
        setState(() {
          _saveFailureTitle = l10n.editProfileGenericErrorTitle;
          _saveFailureMessage =
              profileController.lastProfileWriteErrorMessage ??
              l10n.editProfileSaveFailedMessage;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inputTheme = _inputDecorationTheme(context);
    final l10n = AppLocalizations.of(context)!;
    final displayNameLabel = _isClub
        ? l10n.editProfileClubNameLabel
        : _isRecruiter
        ? l10n.editProfileDisplayNameLabel
        : l10n.editProfileFullNameLabel;
    final headerTitle = _isPlayer
        ? user.role == 'coach'
              ? l10n.profilePublicTitleCoach
              : l10n.editProfileHeaderTitlePlayer
        : _isClub
        ? l10n.editProfileHeaderTitleClub
        : _isRecruiter
        ? user.isAgent
              ? l10n.editProfileHeaderTitleAgent
              : l10n.editProfileHeaderTitleRecruiter
        : l10n.profileFallbackTitle;
    final headerSubtitle = _isPlayer
        ? user.role == 'coach'
              ? l10n.editProfileHeaderSubtitleCoach
              : l10n.editProfileHeaderSubtitlePlayer
        : _isClub
        ? l10n.editProfileHeaderSubtitleClub
        : _isRecruiter
        ? user.isAgent
              ? l10n.editProfileHeaderSubtitleAgent
              : l10n.editProfileHeaderSubtitleRecruiter
        : l10n.editProfileHeaderSubtitleDefault;
    final generalInfoSubtitle = _isClub
        ? l10n.editProfileGeneralInfoSubtitleClub
        : _isRecruiter
        ? l10n.editProfileGeneralInfoSubtitleRecruiter
        : l10n.editProfileGeneralInfoSubtitleDefault;
    final bioLabel = _isPlayer
        ? user.role == 'coach'
              ? l10n.profileBioTitleCoach
              : l10n.profileBioTitlePlayer
        : _isClub
        ? l10n.profileBioTitleClub
        : _isRecruiter
        ? user.isAgent
              ? l10n.profileBioTitleAgent
              : l10n.profileBioTitleRecruiter
        : l10n.profileBioTitleDefault;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackNavigation(result: result);
      },
      child: Scaffold(
        backgroundColor: kSurface,
        appBar: AdAppBar(title: l10n.editProfileAppBarTitle),
        body: Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: inputTheme,
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 18,
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: kPrimary,
                side: const BorderSide(color: kPrimary, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 18,
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: kPrimary),
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (_, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Form(
                      key: _formKey,
                      onChanged: () => _isDirty = true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AdFormHeaderCard(
                            title: headerTitle,
                            subtitle: headerSubtitle,
                            icon: _isPlayer
                                ? Icons.person_pin_circle_outlined
                                : _isClub
                                ? Icons.groups_outlined
                                : _isRecruiter
                                ? Icons.badge_outlined
                                : Icons.person_outline,
                          ),
                          if (_saveFailureMessage != null) ...[
                            const SizedBox(height: 16),
                            ProfileActionNotice(
                              title:
                                  _saveFailureTitle ??
                                  l10n.editProfileSaveFailureFallbackTitle,
                              message: _saveFailureMessage!,
                            ),
                          ],
                          const SizedBox(height: 16),
                          AdSectionCard(
                            title: l10n.editProfileGeneralInfoSectionTitle,
                            subtitle: generalInfoSubtitle,
                            icon: Icons.badge_rounded,
                            child: Column(
                              children: [
                                _buildTextField(
                                  controller: _nomController,
                                  label: displayNameLabel,
                                  icon: Icons.person_outline,
                                  validator: (value) {
                                    final text = (value ?? '').trim();
                                    if (text.isEmpty) {
                                      return l10n
                                          .editProfileNameRequiredValidator;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                _buildTextField(
                                  controller: _phoneController,
                                  label: l10n.editProfilePhoneLabel,
                                  icon: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                ),
                                const SizedBox(height: 12),
                                _buildTextField(
                                  controller: _languagesController,
                                  label: l10n.editProfileLanguagesLabel,
                                  icon: Icons.language_outlined,
                                  hint: l10n.editProfileLanguagesHint,
                                ),
                                if (_isPlayer) ...[
                                  const SizedBox(height: 12),
                                  _buildBirthDateField(context, l10n),
                                ],
                                const SizedBox(height: 12),
                                _buildTextField(
                                  controller: _bioController,
                                  label: bioLabel,
                                  icon: Icons.info_outline,
                                  maxLines: 3,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_isPlayer)
                            AdSectionCard(
                              title: user.role == 'coach'
                                  ? l10n.editProfileCoachFrameTitle
                                  : l10n.editProfilePlayerIdentityTitle,
                              subtitle: user.role == 'coach'
                                  ? l10n.editProfileCoachFrameSubtitle
                                  : l10n.editProfilePlayerIdentitySubtitle,
                              icon: Icons.sports_soccer_outlined,
                              child: Column(
                                children: [
                                  // Le champ libre n'est propose qu'au coach :
                                  // le joueur coche ses postes dans la liste
                                  // fermee du profil avance, la seule que la
                                  // recherche sache filtrer.
                                  if (_isCoach) ...[
                                    _buildTextField(
                                      controller: _positionController,
                                      label: l10n.profileCoachRoleLabel,
                                      icon: Icons.sports_outlined,
                                      hint: l10n.editProfilePositionHint,
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  _buildTextField(
                                    controller: _teamController,
                                    label: user.role == 'coach'
                                        ? l10n.editProfileCoachClubLabel
                                        : l10n.profileCurrentClubLabel,
                                    icon: Icons.flag_outlined,
                                    hint: l10n.editProfileClubHint,
                                  ),
                                ],
                              ),
                            )
                          else if (_isClub)
                            AdSectionCard(
                              title: l10n.editProfileClubFrameTitle,
                              subtitle: l10n.editProfileClubFrameSubtitle,
                              icon: Icons.stadium_outlined,
                              child: Column(
                                children: [
                                  _buildTextField(
                                    controller: _ligueController,
                                    label: l10n.editProfileLeagueLabel,
                                    icon: Icons.emoji_events_outlined,
                                    hint: l10n.editProfileLeagueHint,
                                  ),
                                ],
                              ),
                            )
                          else if (_isRecruiter)
                            AdSectionCard(
                              title: user.isAgent
                                  ? l10n.profilePublicTitleAgent
                                  : l10n.editProfileRecruitmentReferencesTitle,
                              subtitle: user.isAgent
                                  ? l10n
                                        .editProfileRecruitmentReferencesSubtitleAgent
                                  : l10n
                                        .editProfileRecruitmentReferencesSubtitleDefault,
                              icon: Icons.search_rounded,
                              child: Column(
                                children: [
                                  _buildTextField(
                                    controller: _entrepriseController,
                                    label: user.isAgent
                                        ? l10n.profileAgencyLabel
                                        : l10n
                                              .editProfileRecruitmentStructureLabel,
                                    icon: Icons.apartment_outlined,
                                    hint: user.isAgent
                                        ? l10n.editProfileAgencyHint
                                        : l10n
                                              .editProfileRecruitmentStructureHint,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildTextField(
                                    controller: _nombreRecrutementsController,
                                    label: user.isAgent
                                        ? l10n.profilePlacementsLabel
                                        : l10n.profileRecruitmentsLabel,
                                    icon: Icons.how_to_reg_outlined,
                                    keyboardType: TextInputType.number,
                                    validator: (value) =>
                                        _validateOptionalNonNegativeInt(
                                          l10n,
                                          value,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                          AdSectionCard(
                            title: l10n.profileLocationLabel,
                            subtitle: l10n.editProfileLocationSectionSubtitle,
                            icon: Icons.place_outlined,
                            child: Column(
                              children: [
                                _buildTextField(
                                  controller: _cityController,
                                  label: l10n.editProfileCityLabel,
                                  icon: Icons.location_city_outlined,
                                  hint: l10n.editProfileCityHint,
                                ),
                                const SizedBox(height: 12),
                                _buildTextField(
                                  controller: _regionController,
                                  label: l10n.editProfileRegionLabel,
                                  icon: Icons.map_outlined,
                                  hint: l10n.editProfileRegionHint,
                                ),
                                const SizedBox(height: 12),
                                _buildTextField(
                                  controller: _countryController,
                                  label: l10n.editProfileCountryLabel,
                                  icon: Icons.public_outlined,
                                  hint: l10n.editProfileCountryHint,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (user.role == 'joueur') ...[
                            CvUploaderSection(
                              initialUser: user,
                              profileController: profileController,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: AdButton(
              onPressed: _saving ? null : _save,
              loading: _saving,
              leading: Icons.save_rounded,
              label: _saving
                  ? l10n.editProfileSavingAction
                  : l10n.editProfileSaveAction,
            ),
          ),
        ),
      ),
    );
  }
}

class CvUploaderSection extends StatefulWidget {
  final AppUser initialUser;
  final ProfileController profileController;

  static const kPrimary = _EditProfileScreenState.kPrimary;
  const CvUploaderSection({
    super.key,
    required this.initialUser,
    required this.profileController,
  });

  @override
  State<CvUploaderSection> createState() => _CvUploaderSectionState();
}

class _CvUploaderSectionState extends State<CvUploaderSection> {
  String? _cvUrl;
  bool _isUploading = false;
  bool _isDeleting = false;
  String? _cvFailureTitle;
  String? _cvFailureMessage;

  AppUser get _currentUser {
    final liveUser = widget.profileController.user;
    if (liveUser != null && liveUser.uid == widget.initialUser.uid) {
      return liveUser;
    }
    return widget.initialUser;
  }

  @override
  void initState() {
    super.initState();
    _cvUrl = widget.initialUser.cvUrl;
  }

  @override
  void didUpdateWidget(covariant CvUploaderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cvUrl = _currentUser.cvUrl;
  }

  String _maxCvSizeLabel(AppLocalizations l10n) {
    final sizeMb = ProfileController.maxCvPdfBytes ~/ (1024 * 1024);
    return '$sizeMb ${l10n.editProfileCvSizeUnitLabel}';
  }

  void _showCvFailure(String title, String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _cvFailureTitle = title;
      _cvFailureMessage = message;
    });
  }

  void _clearCvFailure() {
    if (!mounted) {
      return;
    }
    setState(() {
      _cvFailureTitle = null;
      _cvFailureMessage = null;
    });
  }

  Future<void> _pickAndUploadCv(AppUser user) async {
    var uploadStarted = false;
    final l10n = AppLocalizations.of(context)!;

    try {
      _clearCvFailure();
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: false,
        withReadStream: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final pickedFile = result.files.single;
      if (pickedFile.size > ProfileController.maxCvPdfBytes) {
        final message = l10n.editProfileCvSizeTooLargeMessage(
          _maxCvSizeLabel(l10n),
        );
        _showCvFailure(l10n.editProfileCvSizeTooLargeTitle, message);
        AdFeedback.error(
          l10n.editProfileCvSizeTooLargeTitle,
          message,
          duration: const Duration(seconds: 6),
        );
        return;
      }

      final bytes = pickedFile.bytes;
      final path = pickedFile.path;
      final readStream = pickedFile.readStream;
      final hasBytes = bytes != null && bytes.isNotEmpty;
      final hasPath = path != null && path.isNotEmpty;
      final hasStream = readStream != null;

      if (!hasBytes && !hasPath && !hasStream) {
        final message = l10n.editProfileCvUnreadableMessage;
        _showCvFailure(l10n.editProfileCvUnreadableTitle, message);
        AdFeedback.error(
          l10n.editProfileCvUnreadableTitle,
          message,
          duration: const Duration(seconds: 6),
        );
        return;
      }

      setState(() => _isUploading = true);
      uploadStarted = true;

      final cvUrl = await widget.profileController.uploadCvPdf(
        user.uid,
        pdfBytes: hasBytes ? bytes : null,
        pdfFile: hasPath ? File(path) : null,
        pdfReadStream: hasStream ? readStream : null,
        byteSize: pickedFile.size > 0 ? pickedFile.size : null,
      );
      if (!mounted) {
        return;
      }
      if (cvUrl == null) {
        setState(() {
          _cvUrl = _currentUser.cvUrl;
          _cvFailureTitle =
              widget.profileController.lastCvUploadErrorTitle ??
              l10n.editProfileCvAddFailedTitle;
          _cvFailureMessage =
              widget.profileController.lastCvUploadErrorMessage ??
              l10n.editProfileCvAddFailedMessage;
        });
        return;
      }
      setState(() {
        _cvUrl = cvUrl;
        _cvFailureTitle = null;
        _cvFailureMessage = null;
      });
    } on ProfileAccessRevokedException {
      return;
    } catch (e, st) {
      AppLogger.debug('CV picker/upload error: $e\n$st');
      final message = l10n.editProfileCvPickUploadFailedMessage;
      _showCvFailure(l10n.editProfileCvAddFailedTitle, message);
      AdFeedback.error(
        l10n.editProfileCvAddFailedTitle,
        message,
        duration: const Duration(seconds: 6),
      );
    } finally {
      if (mounted && uploadStarted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;
    final hasCv = (_cvUrl ?? '').trim().isNotEmpty;
    final l10n = AppLocalizations.of(context)!;

    return AdSectionCard(
      title: l10n.editProfileCvTitle,
      subtitle: l10n.editProfileCvSubtitle,
      icon: Icons.picture_as_pdf_outlined,
      trailing: hasCv
          ? Chip(
              label: Text(l10n.editProfileCvAvailableLabel),
              avatar: const Icon(
                Icons.check_circle,
                color: Colors.white,
                size: 18,
              ),
              backgroundColor: AdColors.success,
              labelStyle: const TextStyle(color: Colors.white),
            )
          : Chip(
              label: Text(l10n.editProfileCvNoneLabel),
              avatar: const Icon(
                Icons.info_outline,
                color: Colors.white,
                size: 18,
              ),
              backgroundColor: AdColors.warning,
              labelStyle: const TextStyle(color: Colors.white),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_cvFailureMessage != null) ...[
            ProfileActionNotice(
              title: _cvFailureTitle ?? l10n.editProfileCvAddFailedTitle,
              message: _cvFailureMessage!,
            ),
            const SizedBox(height: 12),
          ],
          AdButton(
            onPressed: _isUploading || _isDeleting
                ? null
                : () => _pickAndUploadCv(user),
            loading: _isUploading,
            leading: Icons.upload_file_rounded,
            label: _isUploading
                ? l10n.editProfileCvUploadingAction
                : hasCv
                ? l10n.editProfileCvReplaceAction
                : l10n.editProfileCvAddAction,
            kind: AdButtonKind.tonal,
          ),
          if (hasCv) ...[
            const SizedBox(height: 10),
            AdButton(
              onPressed: _isUploading || _isDeleting
                  ? null
                  : () async {
                      try {
                        setState(() => _isDeleting = true);
                        await widget.profileController.deleteCv(user.uid);
                        if (!mounted) {
                          return;
                        }
                        setState(() => _cvUrl = _currentUser.cvUrl);
                      } on ProfileAccessRevokedException {
                        return;
                      } finally {
                        if (mounted) {
                          setState(() => _isDeleting = false);
                        }
                      }
                    },
              loading: _isDeleting,
              leading: Icons.delete_forever_rounded,
              label: _isDeleting
                  ? l10n.editProfileCvDeletingAction
                  : l10n.editProfileCvDeleteAction,
              kind: AdButtonKind.danger,
            ),
          ],
        ],
      ),
    );
  }
}
