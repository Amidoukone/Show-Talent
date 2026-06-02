import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:adfoot/controller/offre_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/offre.dart';
import 'package:intl/intl.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';

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
  final TextEditingController _niveauController = TextEditingController();
  final TextEditingController _posteController = TextEditingController();

  DateTime? _dateDebut;
  DateTime? _dateFin;
  late Map<TextEditingController, String> _initialTextValues;
  DateTime? _initialDateDebut;
  DateTime? _initialDateFin;

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
        _dateFin != _initialDateFin;
  }

  Iterable<TextEditingController> get _textControllers sync* {
    yield _titreController;
    yield _descriptionController;
    yield _localisationController;
    yield _remunerationController;
    yield _niveauController;
    yield _posteController;
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
      _niveauController.text = editingOffre!.niveau ?? '';
      _posteController.text = editingOffre!.posteRecherche ?? '';
    }

    _initialTextValues = <TextEditingController, String>{
      for (final controller in _textControllers) controller: controller.text,
    };
    _initialDateDebut = _dateDebut;
    _initialDateFin = _dateFin;
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
        appBar: AppBar(
          elevation: 0,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          title: Text(isEditing ? 'Modifier l’offre' : 'Nouvelle offre'),
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
                        TextFormField(
                          controller: _posteController,
                          textInputAction: TextInputAction.next,
                          decoration: _buildInputDecoration(
                            'Poste recherché',
                            'Ex: Attaquant, milieu relayeur',
                            Icons.sports_soccer,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _niveauController,
                          textInputAction: TextInputAction.next,
                          decoration: _buildInputDecoration(
                            'Niveau / Section',
                            'Ex: U19, Sénior, Pro',
                            Icons.leaderboard_outlined,
                          ),
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
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitLocked ? null : _submitForm,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                isEditing ? 'Mettre à jour' : 'Publier l’offre',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AdSpacing.md),
      decoration: BoxDecoration(
        color: AdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AdRadius.lg),
        border: Border.all(color: AdColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(title, Theme.of(context).colorScheme),
          const SizedBox(height: 16),
          ...children,
        ],
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
      niveau: _niveauController.text.trim().isEmpty
          ? null
          : _niveauController.text.trim(),
      posteRecherche: _posteController.text.trim().isEmpty
          ? null
          : _posteController.text.trim(),
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
    if (Get.isSnackbarOpen) {
      Get.closeCurrentSnackbar();
    }

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
    _niveauController.dispose();
    _posteController.dispose();
    super.dispose();
  }
}
