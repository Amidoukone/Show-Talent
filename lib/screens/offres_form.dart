import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:adfoot/controller/offre_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/models/offre.dart';
import 'package:intl/intl.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_surface_card.dart';

class OffreFormResult {
  const OffreFormResult({
    required this.title,
    required this.message,
    this.kind = 'success',
  });

  final String title;
  final String message;
  final String kind;

  Map<String, String> toRouteArguments() {
    return <String, String>{
      'offerSystemNoticeTitle': title,
      'offerSystemNoticeMessage': message,
      'offerSystemNoticeKind': kind,
    };
  }
}

class OffreFormScreen extends StatefulWidget {
  const OffreFormScreen({super.key});

  @override
  State<OffreFormScreen> createState() => OffreFormScreenState();
}

/// Classe publique (évite l'erreur "private type in public API")
class OffreFormScreenState extends State<OffreFormScreen> {
  static const int _maxTitleLength = 120;
  static const int _minDescriptionLength = 20;
  static const int _maxDescriptionLength = 1200;

  final OffreController offreController = Get.find();
  final UserController userController = Get.find<UserController>();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titreController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _localisationController = TextEditingController();
  final TextEditingController _remunerationController = TextEditingController();
  List<FootballPosition> _positionCodes = <FootballPosition>[];
  List<AgeCategory> _ageCategories = <AgeCategory>[];
  ClubLevel? _clubLevel;

  DateTime? _dateDebut;
  DateTime? _dateFin;
  late Map<TextEditingController, String> _initialTextValues;
  DateTime? _initialDateDebut;
  DateTime? _initialDateFin;
  late List<FootballPosition> _initialPositionCodes;
  late List<AgeCategory> _initialAgeCategories;
  ClubLevel? _initialClubLevel;

  late bool isEditing;
  late final String _draftOfferId;
  Offre? editingOffre;
  bool _isSubmitting = false;
  bool _hasCompletedSubmit = false;

  bool get _submitLocked => _isSubmitting || _hasCompletedSubmit;
  bool get _hasUnsavedChanges {
    if (_hasCompletedSubmit) return false;
    final textChanged = _initialTextValues.entries.any(
      (entry) => entry.key.text.trim() != entry.value,
    );
    return textChanged ||
        _dateDebut != _initialDateDebut ||
        _dateFin != _initialDateFin ||
        _clubLevel != _initialClubLevel ||
        !_sameSelection(_positionCodes, _initialPositionCodes) ||
        !_sameSelection(_ageCategories, _initialAgeCategories);
  }

  /// Compare deux sélections sans tenir compte de l'ordre.
  ///
  /// Les puces s'ajoutent dans l'ordre où on les touche, donc `[LB, ST]` et
  /// `[ST, LB]` sont la même sélection. Les comparer telles quelles ferait
  /// passer un décochage suivi d'un recochage pour une modification, et le
  /// garde de sortie demanderait confirmation pour rien.
  ///
  /// Une puce ne peut pas être cochée deux fois, donc comparer la taille puis
  /// l'appartenance suffit — pas besoin de compter les doublons.
  static bool _sameSelection<T>(List<T> current, List<T> initial) {
    if (current.length != initial.length) return false;
    return current.every(initial.contains);
  }

  Iterable<TextEditingController> get _textControllers sync* {
    yield _titreController;
    yield _descriptionController;
    yield _localisationController;
    yield _remunerationController;
  }

  @override
  void initState() {
    super.initState();
    isEditing = Get.arguments != null;
    _draftOfferId = const Uuid().v4();

    if (isEditing) {
      editingOffre = Get.arguments as Offre;
      _titreController.text = editingOffre!.titre;
      _descriptionController.text = editingOffre!.description;
      _dateDebut = editingOffre!.dateDebut;
      _dateFin = editingOffre!.dateFin;
      _localisationController.text = editingOffre!.localisation ?? '';
      _remunerationController.text = editingOffre!.remuneration ?? '';
      _positionCodes = List<FootballPosition>.of(editingOffre!.positionCodes);
      _ageCategories = List<AgeCategory>.of(editingOffre!.ageCategories);
      _clubLevel = editingOffre!.clubLevel;
    }

    _initialTextValues = <TextEditingController, String>{
      for (final controller in _textControllers) controller: controller.text,
    };
    _initialDateDebut = _dateDebut;
    _initialDateFin = _dateFin;
    // Des copies, pas les listes elles-memes : les puces les modifient en
    // place, et une reference partagee ferait que l'etat initial suive
    // chaque clic -- le garde ne verrait plus jamais de changement.
    _initialPositionCodes = List<FootballPosition>.of(_positionCodes);
    _initialAgeCategories = List<AgeCategory>.of(_ageCategories);
    _initialClubLevel = _clubLevel;
    for (final controller in _textControllers) {
      controller.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AdAppBar(
          title: isEditing ? 'Modifier l’offre' : 'Nouvelle offre',
          subtitle: 'Opportunité sportive',
          showBottomDivider: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: cs.onSurface),
            onPressed: _handleBackNavigation,
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFormSection(
                      title: 'Résumé',
                      children: [
                        TextFormField(
                          controller: _titreController,
                          maxLength: _maxTitleLength,
                          textInputAction: TextInputAction.next,
                          decoration: _buildInputDecoration(
                            'Titre de l’offre',
                            'Ex: Recherche latéral droit U19',
                            Icons.work_outline,
                          ),
                          validator: _validateTitle,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionController,
                          maxLength: _maxDescriptionLength,
                          minLines: 5,
                          maxLines: 8,
                          decoration: _buildInputDecoration(
                            'Description',
                            'Profil, contexte, attentes et prochaines étapes',
                            Icons.description_outlined,
                          ),
                          validator: _validateDescription,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildFormSection(
                      title: 'Profil recherché',
                      children: [
                        // Le poste se choisit, il ne se tape plus : c'est
                        // ce qui permet a cette offre de rencontrer les
                        // joueurs qui declarent le meme code.
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Postes recherchés *',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Un `FormField` plutot qu'un controle dans
                        // `_submitForm` : le poste devient obligatoire au
                        // meme titre que le titre et la description, il est
                        // valide par le meme `validate()`, et l'erreur
                        // s'affiche sous les puces au lieu d'un message
                        // general qui ne dit pas ou regarder.
                        FormField<List<FootballPosition>>(
                          initialValue: _positionCodes,
                          validator: _validatePositions,
                          builder: (state) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: FootballPosition.values.map((
                                    position,
                                  ) {
                                    final isSelected = _positionCodes.contains(
                                      position,
                                    );
                                    return FilterChip(
                                      selected: isSelected,
                                      label: Text(position.labelFr),
                                      onSelected: (_) {
                                        setState(() {
                                          if (isSelected) {
                                            _positionCodes.remove(position);
                                          } else {
                                            _positionCodes.add(position);
                                          }
                                        });
                                        state.didChange(_positionCodes);
                                      },
                                    );
                                  }).toList(),
                                ),
                                if (state.hasError) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    state.errorText!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Catégories visées',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: AgeCategory.values.map((category) {
                            final isSelected =
                                _ageCategories.contains(category);
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
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<ClubLevel>(
                          initialValue: _clubLevel,
                          decoration: _buildInputDecoration(
                            'Niveau de la structure',
                            '',
                            Icons.leaderboard_outlined,
                          ),
                          items: ClubLevel.values
                              .map(
                                (level) => DropdownMenuItem<ClubLevel>(
                                  value: level,
                                  child: Text(level.labelFr),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _clubLevel = value),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _localisationController,
                          textInputAction: TextInputAction.next,
                          decoration: _buildInputDecoration(
                            'Localisation',
                            'Ville, pays ou région',
                            Icons.place_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildFormSection(
                      title: 'Conditions',
                      children: [
                        TextFormField(
                          controller: _remunerationController,
                          textInputAction: TextInputAction.done,
                          decoration: _buildInputDecoration(
                            'Rémunération (optionnel)',
                            'Ex: 2k-3k €/mois',
                            Icons.payments_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildFormSection(
                      title: 'Période',
                      children: [
                        _buildDatePicker(
                          'Date de début',
                          _dateDebut,
                          _setStartDate,
                          isStart: true,
                        ),
                        const SizedBox(height: 16),
                        _buildDatePicker(
                          'Date de fin',
                          _dateFin,
                          _setEndDate,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    AdButton(
                      onPressed: _submitLocked ? null : _submitForm,
                      loading: _isSubmitting,
                      leading: isEditing
                          ? Icons.save_rounded
                          : Icons.publish_rounded,
                      label: isEditing ? 'Mettre à jour' : 'Publier l’offre',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // UI HELPERS
  // =========================================================

  Widget _buildSectionTitle(String title, ColorScheme cs) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: cs.onSurface,
      ),
    );
  }

  Widget _buildFormSection({
    required String title,
    required List<Widget> children,
  }) {
    return SizedBox(
      width: double.infinity,
      child: AdSurfaceCard(
        padding: const EdgeInsets.all(AdSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(title, Theme.of(context).colorScheme),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(
    String label,
    String hint,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: AdColors.brand),
      filled: true,
      fillColor: AdColors.surfaceCard,
      labelStyle: const TextStyle(color: AdColors.onSurface),
      hintStyle: const TextStyle(color: AdColors.onSurfaceMuted),
    );
  }

  String? _validateTitle(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return 'Le titre est requis.';
    }
    if (normalized.length > _maxTitleLength) {
      return 'Limitez le titre à $_maxTitleLength caractères.';
    }
    return null;
  }

  String? _validateDescription(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return 'La description est requise.';
    }
    if (normalized.length < _minDescriptionLength) {
      return 'Ajoutez au moins $_minDescriptionLength caractères.';
    }
    if (normalized.length > _maxDescriptionLength) {
      return 'Limitez la description à $_maxDescriptionLength caractères.';
    }
    return null;
  }

  /// Le poste est obligatoire, et ce n'est pas une exigence de formulaire.
  ///
  /// Le fil des offres filtre `positionCodes` avec `arrayContainsAny`, cote
  /// serveur. Une offre publiee sans poste ne remonte donc dans aucun filtre
  /// par poste -- pas « moins souvent » : jamais. Elle n'est visible que dans
  /// la liste non filtree, c'est-a-dire de moins en moins a mesure que le
  /// catalogue grossit, et son auteur n'a aucun moyen de s'en apercevoir.
  String? _validatePositions(List<FootballPosition>? positions) {
    if (positions == null || positions.isEmpty) {
      return 'Choisissez au moins un poste : sans lui, l’offre '
          'n’apparaît dans aucune recherche par poste.';
    }
    return null;
  }

  void _setStartDate(DateTime picked) {
    setState(() {
      _dateDebut = picked;
      if (_dateFin != null && _dateFin!.isBefore(picked)) {
        _dateFin = null;
      }
    });
  }

  void _setEndDate(DateTime picked) {
    setState(() => _dateFin = picked);
  }

  Future<void> _handleBackNavigation() async {
    if (_isSubmitting) {
      return;
    }

    if (!_hasUnsavedChanges) {
      Get.back();
      return;
    }

    final discard = await AdDialogs.confirm(
      context: context,
      title: 'Quitter sans enregistrer ?',
      message: 'Les modifications de cette offre ne seront pas conservées.',
      confirmLabel: 'Quitter',
      cancelLabel: 'Continuer',
      danger: true,
    );
    if (discard && mounted) {
      Get.back();
    }
  }

  Widget _buildDatePicker(
    String label,
    DateTime? date,
    Function(DateTime) onDateSelected, {
    bool isStart = false,
  }) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final firstDate = _resolveFirstDate(
          now: now,
          selectedDate: date,
          isStart: isStart,
        );
        final initialDate = _resolveInitialDate(
          selectedDate: date,
          firstDate: firstDate,
        );

        final pickedDate = await showDatePicker(
          context: context,
          locale: const Locale('fr', 'FR'),
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: DateTime(2100),
        );

        if (pickedDate != null) {
          onDateSelected(pickedDate);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        decoration: BoxDecoration(
          border: Border.all(color: AdColors.divider),
          borderRadius: BorderRadius.circular(16),
          color: AdColors.surfaceCard,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: AdColors.onSurfaceMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              date != null
                  ? DateFormat('dd MMM yyyy', 'fr_FR').format(date)
                  : 'Choisir une date',
              style: const TextStyle(
                fontSize: 16,
                color: AdColors.brand,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _resolveFirstDate({
    required DateTime now,
    required DateTime? selectedDate,
    required bool isStart,
  }) {
    if (isStart) {
      if (isEditing && selectedDate != null && selectedDate.isBefore(now)) {
        return selectedDate;
      }
      return now;
    }

    final minDate = _dateDebut ?? now;
    if (isEditing && selectedDate != null && selectedDate.isBefore(minDate)) {
      return selectedDate;
    }
    return minDate;
  }

  DateTime _resolveInitialDate({
    required DateTime? selectedDate,
    required DateTime firstDate,
  }) {
    if (selectedDate == null || selectedDate.isBefore(firstDate)) {
      return firstDate;
    }
    return selectedDate;
  }

  // =========================================================
  // SUBMIT
  // =========================================================

  Future<void> _submitForm() async {
    if (_submitLocked) return;

    if (!_formKey.currentState!.validate() ||
        _dateDebut == null ||
        _dateFin == null) {
      AdFeedback.error(
        'Erreur',
        'Veuillez renseigner les informations obligatoires et la période.',
      );
      return;
    }

    if (_dateDebut!.isAfter(_dateFin!)) {
      AdFeedback.error(
        'Erreur',
        'La date de début doit précéder la date de fin.',
      );
      return;
    }

    final currentUser = userController.user;
    if (currentUser == null) {
      AdFeedback.error(
        'Erreur',
        'Utilisateur introuvable. Merci de vous reconnecter.',
      );
      return;
    }

    final titre = _titreController.text.trim();
    final description = _descriptionController.text.trim();
    final titleValidation = _validateTitle(titre);
    final descriptionValidation = _validateDescription(description);
    if (titleValidation != null || descriptionValidation != null) {
      AdFeedback.error(
        'Erreur',
        titleValidation ?? descriptionValidation!,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final offre = Offre(
      id: isEditing ? editingOffre!.id : _draftOfferId,
      titre: titre,
      description: description,
      dateDebut: _dateDebut!,
      dateFin: _dateFin!,
      recruteur: currentUser,
      candidats: isEditing ? editingOffre!.candidats : [],
      statut:
          isEditing ? Offre.normalizeStatus(editingOffre!.statut) : 'ouverte',
      dateCreation: isEditing ? editingOffre!.dateCreation : DateTime.now(),
      localisation: _localisationController.text.trim().isEmpty
          ? null
          : _localisationController.text.trim(),
      remuneration: _remunerationController.text.trim().isEmpty
          ? null
          : _remunerationController.text.trim(),
      positionCodes: _positionCodes,
      ageCategories: _ageCategories,
      clubLevel: _clubLevel,
      pieceJointeUrl: null,
      vues: isEditing ? (editingOffre!.vues ?? 0) : 0,
      viewedBy: isEditing ? (editingOffre!.viewedBy ?? <String>[]) : <String>[],
      archivedAt: isEditing ? editingOffre!.archivedAt : null,
      lastUpdated: isEditing ? editingOffre!.lastUpdated : null,
    );

    try {
      final response = isEditing
          ? await offreController.modifierOffre(offre, currentUser)
          : await offreController.publierOffre(offre, currentUser);

      if (!response.success) {
        if (response.toast == ToastLevel.none) {
          return;
        }
        AdFeedback.error(
          'Erreur',
          response.message,
        );
        return;
      }

      if (mounted) {
        setState(() => _hasCompletedSubmit = true);
      } else {
        _hasCompletedSubmit = true;
      }

      _navigateAfterSuccessfulSubmit(response.message);
    } finally {
      if (mounted && !_hasCompletedSubmit) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _navigateAfterSuccessfulSubmit(String message) {
    AdFeedback.dismissCurrent();

    final result = OffreFormResult(
      title: isEditing ? 'Offre mise à jour' : 'Offre publiée',
      message: message,
    );
    final navigator = Get.key.currentState;
    if (navigator?.canPop() ?? false) {
      Get.back(result: result);
    } else {
      Get.offAllNamed(
        AppRoutes.main,
        arguments: <String, dynamic>{
          'tab': 1,
          ...result.toRouteArguments(),
        },
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers) {
      controller.removeListener(_onTextChanged);
    }
    _titreController.dispose();
    _descriptionController.dispose();
    _localisationController.dispose();
    _remunerationController.dispose();
    super.dispose();
  }
}
