import 'dart:io';

import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_surface_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class EventFormResult {
  const EventFormResult({
    required this.title,
    required this.message,
    this.kind = 'success',
  });

  final String title;
  final String message;
  final String kind;
}

class EventFormScreen extends StatefulWidget {
  final Event? event;

  const EventFormScreen({super.key, this.event});

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  static const int _maxTitleLength = 120;
  static const int _minDescriptionLength = 20;
  static const int _maxDescriptionLength = 1200;

  final EventController eventController = Get.find<EventController>();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController titleController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController capacityController = TextEditingController();
  final TextEditingController tagsController = TextEditingController();

  DateTime? startDate;
  DateTime? endDate;
  late final String _draftEventId;
  late Map<TextEditingController, String> _initialTextValues;
  DateTime? _initialStartDate;
  DateTime? _initialEndDate;
  late bool _initialEstPublic;
  late String _initialStatut;

  bool estPublic = true;
  String statut = 'ouvert';
  bool _isSubmitting = false;
  bool _hasCompletedSubmit = false;

  final ImagePicker _imagePicker = ImagePicker();

  /// L'affiche deja publiee, si l'evenement en a une.
  String? _flyerUrl;

  /// Le fichier choisi mais pas encore televerse.
  ///
  /// Il ne peut pas partir avant que l'evenement existe : la regle de stockage
  /// lit le document pour savoir qui televerse. Il attend donc ici jusqu'a ce
  /// que la creation ou la mise a jour ait abouti.
  String? _pickedFlyerPath;

  /// L'organisateur a demande le retrait de l'affiche existante.
  bool _flyerRemoved = false;

  bool get _hasFlyerChange => _pickedFlyerPath != null || _flyerRemoved;

  /// Ce que l'ecran doit montrer maintenant, quel que soit l'etat du reste.
  String? get _visibleFlyerUrl => _flyerRemoved ? null : _flyerUrl;

  bool get _submitLocked => _isSubmitting || _hasCompletedSubmit;

  Iterable<TextEditingController> get _textControllers sync* {
    yield titleController;
    yield descriptionController;
    yield locationController;
    yield capacityController;
    yield tagsController;
  }

  bool get _hasUnsavedChanges {
    if (_hasCompletedSubmit) return false;
    final textChanged = _initialTextValues.entries.any(
      (entry) => entry.key.text.trim() != entry.value,
    );
    return textChanged ||
        _hasFlyerChange ||
        startDate != _initialStartDate ||
        endDate != _initialEndDate ||
        estPublic != _initialEstPublic ||
        statut != _initialStatut;
  }

  @override
  void initState() {
    super.initState();
    _draftEventId = eventController.newEventId();
    _flyerUrl = widget.event?.flyerUrl;

    if (widget.event != null) {
      titleController.text = widget.event!.titre;
      descriptionController.text = widget.event!.description;
      locationController.text = widget.event!.lieu;
      capacityController.text = widget.event!.capaciteMax != null
          ? widget.event!.capaciteMax.toString()
          : '';
      tagsController.text = widget.event!.tags?.join(', ') ?? '';
      startDate = widget.event!.dateDebut;
      endDate = widget.event!.dateFin;
      estPublic = widget.event!.estPublic;
      statut = Event.normalizeStatus(widget.event!.statut);
    }

    _initialTextValues = <TextEditingController, String>{
      for (final controller in _textControllers) controller: controller.text,
    };
    _initialStartDate = startDate;
    _initialEndDate = endDate;
    _initialEstPublic = estPublic;
    _initialStatut = statut;
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
        resizeToAvoidBottomInset: true,
        appBar: AdAppBar(
          title: widget.event != null
              ? 'Modifier l’événement'
              : 'Créer un événement',
          subtitle: 'Publication encadrée',
          showBottomDivider: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _handleBackNavigation();
            },
          ),
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
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
                          _buildTextField(
                            controller: titleController,
                            labelText: 'Titre',
                            hintText: 'Saisissez le titre de l’événement',
                            icon: Icons.title,
                            maxLength: _maxTitleLength,
                            validator: _validateTitle,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: descriptionController,
                            labelText: 'Description',
                            hintText: 'Décrivez l’événement',
                            icon: Icons.description,
                            maxLines: 5,
                            maxLength: _maxDescriptionLength,
                            validator: _validateDescription,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: 'Organisation',
                        children: [
                          _buildTextField(
                            controller: locationController,
                            labelText: 'Lieu',
                            hintText: 'Ville, stade ou adresse',
                            icon: Icons.location_on,
                            validator: _validateRequiredLocation,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: capacityController,
                            labelText: 'Capacité maximale (optionnel)',
                            hintText: 'Ex: 50',
                            icon: Icons.groups,
                            keyboardType: TextInputType.number,
                            validator: _validateOptionalCapacity,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: tagsController,
                            labelText: 'Tags / Catégories',
                            hintText: 'Ex: U19, Détection, Futsal',
                            icon: Icons.sell_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: 'Accès',
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Événement public'),
                            subtitle: const Text(
                              'Désactivez pour rendre l’événement privé',
                            ),
                            value: estPublic,
                            onChanged: (v) => setState(() => estPublic = v),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: statut,
                            decoration: InputDecoration(
                              labelText: 'Statut',
                              prefixIcon: const Icon(
                                Icons.flag_outlined,
                                color: AdColors.brand,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AdRadius.lg),
                              ),
                              filled: true,
                              fillColor: AdColors.surfaceCard,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'brouillon',
                                child: Text('Brouillon'),
                              ),
                              DropdownMenuItem(
                                value: 'ouvert',
                                child: Text('Ouvert'),
                              ),
                              DropdownMenuItem(
                                value: 'ferme',
                                child: Text('Fermé'),
                              ),
                              DropdownMenuItem(
                                value: 'archive',
                                child: Text('Archivé'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => statut = v ?? 'ouvert'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: 'Dates',
                        children: [
                          _buildDatePicker(
                            'Date de début',
                            startDate,
                            _setStartDate,
                            isStart: true,
                          ),
                          const SizedBox(height: 16),
                          _buildDatePicker(
                            'Date de fin',
                            endDate,
                            _setEndDate,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: 'Affiche',
                        children: [_buildFlyerPicker()],
                      ),
                      const SizedBox(height: 24),
                      AdButton(
                        onPressed: _submitLocked ? null : _handleSubmit,
                        loading: _isSubmitting,
                        leading: widget.event != null
                            ? Icons.save_rounded
                            : Icons.publish_rounded,
                        label: widget.event != null
                            ? 'Mettre à jour'
                            : 'Publier l’événement',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Choisit une affiche, sans la televerser.
  ///
  /// Compresse a la prise : la regle de stockage plafonne a 8 Mo, et une photo
  /// de telephone recente depasse ce plafond assez souvent pour que refuser
  /// apres coup soit une mauvaise reponse. 1600 px de cote suffisent
  /// largement pour une affiche affichee en pleine largeur.
  Future<void> _pickFlyer() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _pickedFlyerPath = picked.path;
        _flyerRemoved = false;
      });
    } catch (error) {
      if (!mounted) return;
      AdFeedback.error(
        'Affiche',
        'Impossible d\u2019ouvrir la galerie.',
      );
      AppLogger.warning(
        'Selection affiche evenement echouee: $error',
        source: 'EventFormScreen._pickFlyer',
        error: error,
      );
    }
  }

  void _clearFlyer() {
    setState(() {
      _pickedFlyerPath = null;
      // Ne marquer un retrait que s'il y a quelque chose a retirer en base :
      // annuler un choix local ne doit pas declencher une suppression.
      _flyerRemoved = _flyerUrl != null;
    });
  }

  Widget _buildFlyerPicker() {
    final localPath = _pickedFlyerPath;
    final remoteUrl = _visibleFlyerUrl;
    final hasSomething = localPath != null || remoteUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Une affiche donne a votre evenement le format que le football '
          'amateur partage deja. Facultative.',
          style: TextStyle(color: AdColors.onSurfaceMuted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        if (hasSomething)
          ClipRRect(
            borderRadius: BorderRadius.circular(AdRadius.md),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: localPath != null
                  ? Image.file(File(localPath), fit: BoxFit.cover)
                  : Image.network(
                      remoteUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => ColoredBox(
                        color: AdColors.surfaceCard,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
            ),
          ),
        if (hasSomething) const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _submitLocked ? null : _pickFlyer,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  hasSomething ? 'Remplacer' : 'Ajouter une affiche',
                ),
              ),
            ),
            if (hasSomething) ...[
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _submitLocked ? null : _clearFlyer,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Retirer'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Applique le changement d'affiche, une fois l'evenement ecrit.
  ///
  /// Renvoie le message a ajouter au retour, ou une chaine vide. Un echec ne
  /// remet pas la publication en cause : l'evenement existe, il lui manque une
  /// image, et le dire vaut mieux que faire croire a un echec complet.
  Future<String> _applyFlyerChange(String eventId) async {
    final localPath = _pickedFlyerPath;

    if (localPath != null) {
      final response = await eventController.attachFlyer(
        eventId: eventId,
        filePath: localPath,
      );
      return response.success ? '' : ' L\u2019affiche n\u2019a pas pu etre ajoutee.';
    }

    if (_flyerRemoved && _flyerUrl != null) {
      final response = await eventController.removeFlyer(eventId);
      return response.success ? '' : ' L\u2019affiche n\u2019a pas pu etre retiree.';
    }

    return '';
  }

  Future<void> _handleSubmit() async {
    if (_submitLocked) return;

    if (!(_formKey.currentState?.validate() ?? false) ||
        startDate == null ||
        endDate == null) {
      AdFeedback.error(
        'Erreur',
        'Veuillez remplir tous les champs obligatoires.',
      );
      return;
    }

    if (endDate!.isBefore(startDate!)) {
      AdFeedback.error(
        'Erreur date',
        'La date de fin doit être après la date de début.',
      );
      return;
    }

    int? capacite;
    if (capacityController.text.trim().isNotEmpty) {
      capacite = int.tryParse(capacityController.text.trim());
      if (capacite == null || capacite <= 0) {
        AdFeedback.error(
          'Capacité invalide',
          'Entrez un nombre positif.',
        );
        return;
      }
    }

    final tags = tagsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final AppUser? currentUser = Get.find<UserController>().user;
    if (currentUser == null) {
      AdFeedback.error(
        'Erreur',
        'Utilisateur introuvable. Merci de vous reconnecter.',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (widget.event != null) {
        final updatedEvent = Event(
          id: widget.event!.id,
          titre: titleController.text.trim(),
          description: descriptionController.text.trim(),
          dateDebut: startDate!,
          dateFin: endDate!,
          organisateur: widget.event!.organisateur,
          participants: widget.event!.participants,
          statut: Event.normalizeStatus(statut),
          lieu: locationController.text.trim(),
          estPublic: estPublic,
          createdAt: widget.event!.createdAt,
          capaciteMax: capacite,
          tags: tags.isEmpty ? null : tags,
          streamingUrl: null,
          // Sans cette ligne, editer un evenement effacait son affiche :
          // `updateEvent` supprime le champ quand il vaut null, et le
          // formulaire envoyait null a chaque fois.
          flyerUrl: _visibleFlyerUrl,
          views: widget.event!.views,
          viewedBy: widget.event!.viewedBy,
        );

        final response =
            await eventController.updateEvent(updatedEvent, currentUser);
        if (!mounted) return;

        if (!response.success) {
          if (response.toast == ToastLevel.none) {
            return;
          }
          AdFeedback.error('Erreur', response.message);
          return;
        }

        final flyerNote = await _applyFlyerChange(widget.event!.id);
        if (!mounted) return;

        _completeSubmit('${response.message}$flyerNote');
      } else {
        final newEvent = Event(
          id: _draftEventId,
          titre: titleController.text.trim(),
          description: descriptionController.text.trim(),
          dateDebut: startDate!,
          dateFin: endDate!,
          organisateur: currentUser,
          participants: const [],
          statut: Event.normalizeStatus(statut),
          lieu: locationController.text.trim(),
          estPublic: estPublic,
          createdAt: DateTime.now(),
          capaciteMax: capacite,
          tags: tags.isEmpty ? null : tags,
          streamingUrl: null,
          flyerUrl: null,
          views: 0,
        );

        final response =
            await eventController.createEvent(newEvent, currentUser);
        if (!mounted) return;

        if (!response.success) {
          if (response.toast == ToastLevel.none) {
            return;
          }
          AdFeedback.error('Erreur', response.message);
          return;
        }

        final flyerNote = await _applyFlyerChange(_draftEventId);
        if (!mounted) return;

        _completeSubmit('${response.message}$flyerNote');
      }
    } finally {
      if (mounted && !_hasCompletedSubmit) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _completeSubmit(String message) {
    AdFeedback.dismissCurrent();

    if (mounted) {
      setState(() => _hasCompletedSubmit = true);
    } else {
      _hasCompletedSubmit = true;
    }

    Get.back(
      result: EventFormResult(
        title:
            widget.event != null ? 'Événement mis à jour' : 'Événement publié',
        message: message,
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AdColors.onSurface,
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
            _buildSectionTitle(title),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    int maxLines = 1,
    int? maxLength,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      textInputAction:
          maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Icon(icon, color: AdColors.brand),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdRadius.lg),
        ),
        filled: true,
        fillColor: AdColors.surfaceCard,
        contentPadding: const EdgeInsets.all(20),
      ),
    );
  }

  String? _validateTitle(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return 'Le titre est requis.';
    if (normalized.length > _maxTitleLength) {
      return 'Limitez le titre à $_maxTitleLength caractères.';
    }
    return null;
  }

  String? _validateDescription(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return 'La description est requise.';
    if (normalized.length < _minDescriptionLength) {
      return 'Ajoutez au moins $_minDescriptionLength caractères.';
    }
    if (normalized.length > _maxDescriptionLength) {
      return 'Limitez la description à $_maxDescriptionLength caractères.';
    }
    return null;
  }

  String? _validateRequiredLocation(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return 'Le lieu est requis.';
    return null;
  }

  String? _validateOptionalCapacity(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;
    final capacity = int.tryParse(normalized);
    if (capacity == null || capacity <= 0) {
      return 'Entrez un nombre positif.';
    }
    return null;
  }

  void _setStartDate(DateTime picked) {
    setState(() {
      startDate = picked;
      if (endDate != null && endDate!.isBefore(picked)) {
        endDate = null;
      }
    });
  }

  void _setEndDate(DateTime picked) {
    setState(() => endDate = picked);
  }

  Future<void> _handleBackNavigation() async {
    if (_isSubmitting) return;

    if (!_hasUnsavedChanges) {
      Get.back();
      return;
    }

    final discard = await AdDialogs.confirm(
      context: context,
      title: 'Quitter sans enregistrer ?',
      message: 'Les modifications de cet événement ne seront pas conservées.',
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
    ValueChanged<DateTime> onDateSelected, {
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
          builder: (context, child) {
            return Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: AdColors.brand,
                  onPrimary: AdColors.brandOn,
                  surface: AdColors.surfaceCard,
                  onSurface: AdColors.onSurface,
                ),
                dialogTheme: const DialogThemeData(
                  backgroundColor: AdColors.surfaceCard,
                ),
              ),
              child: child!,
            );
          },
        );

        if (pickedDate == null) return;
        onDateSelected(pickedDate);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        decoration: BoxDecoration(
          border: Border.all(color: AdColors.divider),
          borderRadius: BorderRadius.circular(AdRadius.lg),
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
      if (widget.event != null &&
          selectedDate != null &&
          selectedDate.isBefore(now)) {
        return selectedDate;
      }
      return now;
    }

    final minDate = startDate ?? now;
    if (widget.event != null &&
        selectedDate != null &&
        selectedDate.isBefore(minDate)) {
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

  @override
  void dispose() {
    for (final controller in _textControllers) {
      controller.removeListener(_onTextChanged);
    }
    titleController.dispose();
    descriptionController.dispose();
    locationController.dispose();
    capacityController.dispose();
    tagsController.dispose();
    super.dispose();
  }
}
