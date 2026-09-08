import 'dart:io';

import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/football_vocabulary.dart';
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

  DateTime? startDate;
  DateTime? endDate;
  late final String _draftEventId;
  late Map<TextEditingController, String> _initialTextValues;
  DateTime? _initialStartDate;
  DateTime? _initialEndDate;
  late bool _initialEstPublic;
  late String _initialStatut;

  /// Le vocabulaire footballistique de l'evenement.
  ///
  /// Il remplace le champ « Tags / Categories », qui etait du texte libre :
  /// « U19 », « u19 », « moins de 19 ans » et « U-19 » y designaient la meme
  /// chose sans jamais se rencontrer dans une recherche. Les anciens tags
  /// restent lisibles -- le modele garde le champ, et l'edition le reconduit --
  /// mais aucun nouveau ne se cree ici.
  List<FootballPosition> _positionCodes = <FootballPosition>[];
  List<AgeCategory> _ageCategories = <AgeCategory>[];
  ClubLevel? _clubLevel;

  late List<FootballPosition> _initialPositionCodes;
  late List<AgeCategory> _initialAgeCategories;
  late ClubLevel? _initialClubLevel;

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
        statut != _initialStatut ||
        _clubLevel != _initialClubLevel ||
        !_sameSelection(_positionCodes, _initialPositionCodes) ||
        !_sameSelection(_ageCategories, _initialAgeCategories);
  }

  /// Une puce ne peut pas etre cochee deux fois, donc comparer la taille puis
  /// l'appartenance suffit -- pas besoin de compter les doublons.
  static bool _sameSelection<T>(List<T> current, List<T> initial) {
    if (current.length != initial.length) return false;
    return current.every(initial.contains);
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
      startDate = widget.event!.dateDebut;
      endDate = widget.event!.dateFin;
      estPublic = widget.event!.estPublic;
      statut = Event.normalizeStatus(widget.event!.statut);
      _positionCodes = List<FootballPosition>.of(widget.event!.positionCodes);
      _ageCategories = List<AgeCategory>.of(widget.event!.ageCategories);
      _clubLevel = widget.event!.clubLevel;
    }

    _initialTextValues = <TextEditingController, String>{
      for (final controller in _textControllers) controller: controller.text,
    };
    _initialStartDate = startDate;
    _initialEndDate = endDate;
    _initialEstPublic = estPublic;
    _initialStatut = statut;
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
    final l10n = AppLocalizations.of(context)!;

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
              ? l10n.eventFormEditTitle
              : l10n.eventCreateAction,
          subtitle: l10n.eventFormSubtitle,
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
                        title: l10n.eventFormSummarySectionTitle,
                        children: [
                          _buildTextField(
                            controller: titleController,
                            labelText: l10n.eventFormTitleLabel,
                            hintText: l10n.eventFormTitleHint,
                            icon: Icons.title,
                            maxLength: _maxTitleLength,
                            validator: (value) => _validateTitle(l10n, value),
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: descriptionController,
                            labelText: l10n.offreDescriptionLabel,
                            hintText: l10n.eventFormDescriptionHint,
                            icon: Icons.description,
                            maxLines: 5,
                            maxLength: _maxDescriptionLength,
                            validator: (value) =>
                                _validateDescription(l10n, value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: l10n.eventFormOrganizationSectionTitle,
                        children: [
                          _buildTextField(
                            controller: locationController,
                            labelText: l10n.offreLocationLabel,
                            hintText: l10n.eventFormLocationHint,
                            icon: Icons.location_on,
                            validator: (value) =>
                                _validateRequiredLocation(l10n, value),
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: capacityController,
                            labelText: l10n.eventFormCapacityLabel,
                            hintText: l10n.eventFormCapacityHint,
                            icon: Icons.groups,
                            keyboardType: TextInputType.number,
                            validator: (value) =>
                                _validateOptionalCapacity(l10n, value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: l10n.eventFormSoughtProfileSectionTitle,
                        children: [
                          // Le poste se choisit, il ne se tape plus : c'est ce
                          // qui permet a cet evenement de rencontrer les
                          // joueurs qui declarent le meme code.
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n.eventFormPositionsRequiredLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Un `FormField` plutot qu'un controle dans
                          // `_handleSubmit` : le poste devient obligatoire au
                          // meme titre que le titre, il est valide par le meme
                          // `validate()`, et l'erreur se pose sous les puces au
                          // lieu d'un message general qui ne dit pas ou
                          // regarder. Exactement le choix fait pour l'offre
                          // dans c80719c.
                          FormField<List<FootballPosition>>(
                            initialValue: _positionCodes,
                            validator: (value) =>
                                _validatePositions(l10n, value),
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
                                      final isSelected = _positionCodes
                                          .contains(position);
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
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n.eventFormCategoriesLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: AgeCategory.values.map((category) {
                              final isSelected = _ageCategories.contains(
                                category,
                              );
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
                            decoration: InputDecoration(
                              labelText: l10n.eventFormClubLevelLabel,
                              prefixIcon: const Icon(
                                Icons.leaderboard_outlined,
                                color: AdColors.brand,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AdRadius.lg,
                                ),
                              ),
                              filled: true,
                              fillColor: AdColors.surfaceCard,
                              contentPadding: const EdgeInsets.all(20),
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
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: l10n.eventFormAccessSectionTitle,
                        children: [
                          // Ce reglage decrit votre facon de recruter les
                          // participants, pas la visibilite de l'evenement :
                          // il ne masque rien. Il disait « public / privé »,
                          // ce qui promettait une confidentialite qu'aucune
                          // regle ne tient -- `allow read` sur `events` ne
                          // consulte pas `estPublic`, tout compte actif voit
                          // tous les evenements. Le sous-titre le dit
                          // desormais, faute de pouvoir le corriger sans
                          // decouper le document (meme limite que
                          // `profilePublic`, documentee dans firestore.rules).
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.eventFormOpenRegistrationLabel),
                            subtitle: Text(
                              l10n.eventFormOpenRegistrationSubtitle,
                            ),
                            value: estPublic,
                            onChanged: (v) => setState(() => estPublic = v),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: statut,
                            decoration: InputDecoration(
                              labelText: l10n.profileStatusLabel,
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
                            items: [
                              DropdownMenuItem(
                                value: 'brouillon',
                                child: Text(l10n.eventStatusDraftLabel),
                              ),
                              DropdownMenuItem(
                                value: 'ouvert',
                                child: Text(l10n.eventStatusOpenLabel),
                              ),
                              DropdownMenuItem(
                                value: 'ferme',
                                child: Text(l10n.eventStatusClosedLabel),
                              ),
                              DropdownMenuItem(
                                value: 'archive',
                                child: Text(l10n.eventStatusArchivedLabel),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => statut = v ?? 'ouvert'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: l10n.eventFormDatesSectionTitle,
                        children: [
                          _buildDatePicker(
                            l10n,
                            l10n.eventFormStartDateLabel,
                            startDate,
                            _setStartDate,
                            isStart: true,
                          ),
                          const SizedBox(height: 16),
                          _buildDatePicker(
                            l10n,
                            l10n.eventFormEndDateLabel,
                            endDate,
                            _setEndDate,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFormSection(
                        title: l10n.eventFormFlyerSectionTitle,
                        children: [_buildFlyerPicker(l10n)],
                      ),
                      const SizedBox(height: 24),
                      AdButton(
                        onPressed: _submitLocked ? null : _handleSubmit,
                        loading: _isSubmitting,
                        leading: widget.event != null
                            ? Icons.save_rounded
                            : Icons.publish_rounded,
                        label: widget.event != null
                            ? l10n.eventFormUpdateAction
                            : l10n.eventFormPublishAction,
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
      final l10n = AppLocalizations.of(context)!;
      AdFeedback.error(
        l10n.eventFormFlyerPickErrorTitle,
        l10n.eventFormFlyerPickErrorMessage,
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

  Widget _buildFlyerPicker(AppLocalizations l10n) {
    final localPath = _pickedFlyerPath;
    final remoteUrl = _visibleFlyerUrl;
    final hasSomething = localPath != null || remoteUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.eventFormFlyerHelpText,
          style: const TextStyle(
            color: AdColors.onSurfaceMuted,
            fontSize: 13,
          ),
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
                  hasSomething
                      ? l10n.eventFormFlyerReplaceAction
                      : l10n.eventFormFlyerAddAction,
                ),
              ),
            ),
            if (hasSomething) ...[
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _submitLocked ? null : _clearFlyer,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.eventFormFlyerRemoveAction),
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
  Future<String> _applyFlyerChange(AppLocalizations l10n, String eventId) async {
    final localPath = _pickedFlyerPath;

    if (localPath != null) {
      final response = await eventController.attachFlyer(
        eventId: eventId,
        filePath: localPath,
      );
      return response.success ? '' : l10n.eventFormFlyerAttachFailedNote;
    }

    if (_flyerRemoved && _flyerUrl != null) {
      final response = await eventController.removeFlyer(eventId);
      return response.success ? '' : l10n.eventFormFlyerRemoveFailedNote;
    }

    return '';
  }

  Future<void> _handleSubmit() async {
    if (_submitLocked) return;

    final l10n = AppLocalizations.of(context)!;

    if (!(_formKey.currentState?.validate() ?? false) ||
        startDate == null ||
        endDate == null) {
      AdFeedback.error(
        l10n.eventFormGenericErrorTitle,
        l10n.eventFormMissingFieldsMessage,
      );
      return;
    }

    if (endDate!.isBefore(startDate!)) {
      AdFeedback.error(
        l10n.eventFormDateErrorTitle,
        l10n.eventFormDateErrorMessage,
      );
      return;
    }

    int? capacite;
    if (capacityController.text.trim().isNotEmpty) {
      capacite = int.tryParse(capacityController.text.trim());
      if (capacite == null || capacite <= 0) {
        AdFeedback.error(
          l10n.eventFormInvalidCapacityTitle,
          l10n.eventFormPositiveNumberMessage,
        );
        return;
      }
    }

    final AppUser? currentUser = Get.find<UserController>().user;
    if (currentUser == null) {
      AdFeedback.error(
        l10n.eventFormGenericErrorTitle,
        l10n.commonUserNotFoundMessage,
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
          positionCodes: _positionCodes,
          ageCategories: _ageCategories,
          clubLevel: _clubLevel,
          capaciteMax: capacite,
          // Les anciens tags sont reconduits tels quels : le champ de saisie a
          // disparu, mais effacer ce qu'un organisateur avait ecrit serait une
          // perte de donnee, et la recherche plein texte les lit encore.
          tags: widget.event!.tags,
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
          AdFeedback.error(l10n.eventFormGenericErrorTitle, response.message);
          return;
        }

        final flyerNote = await _applyFlyerChange(l10n, widget.event!.id);
        if (!mounted) return;

        _completeSubmit(l10n, '${response.message}$flyerNote');
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
          positionCodes: _positionCodes,
          ageCategories: _ageCategories,
          clubLevel: _clubLevel,
          capaciteMax: capacite,
          // Plus de tags libres a la creation : le vocabulaire code les
          // remplace, et en creer de nouveaux reviendrait a alimenter le champ
          // qu'on vient de cesser de saisir.
          tags: null,
          streamingUrl: null,
          flyerUrl: null,
          views: 0,
          // Sans elle, `Event.toMap()` omet le champ (`if (viewedBy != null)`)
          // et le premier increment de vues plante sur `resource.data.viewedBy`
          // absent -- une erreur d'evaluation des regles, pas un `null`, qui
          // refuse la toute premiere ecriture qui aurait pu creer le champ.
          // Le pendant exact de offres_form.dart : `viewedBy: <String>[]`.
          viewedBy: const <String>[],
        );

        final response =
            await eventController.createEvent(newEvent, currentUser);
        if (!mounted) return;

        if (!response.success) {
          if (response.toast == ToastLevel.none) {
            return;
          }
          AdFeedback.error(l10n.eventFormGenericErrorTitle, response.message);
          return;
        }

        final flyerNote = await _applyFlyerChange(l10n, _draftEventId);
        if (!mounted) return;

        _completeSubmit(l10n, '${response.message}$flyerNote');
      }
    } finally {
      if (mounted && !_hasCompletedSubmit) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _completeSubmit(AppLocalizations l10n, String message) {
    AdFeedback.dismissCurrent();

    if (mounted) {
      setState(() => _hasCompletedSubmit = true);
    } else {
      _hasCompletedSubmit = true;
    }

    Get.back(
      result: EventFormResult(
        title: widget.event != null
            ? l10n.eventFormUpdatedTitle
            : l10n.eventFormPublishedTitle,
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

  /// Un evenement sans poste est introuvable, pas « moins visible ».
  ///
  /// Le fil interroge `positionCodes` en `arrayContainsAny` : un evenement qui
  /// n'en porte aucun n'apparait dans aucune recherche par poste, et son
  /// organisateur n'a aucun moyen de s'en apercevoir -- l'evenement s'affiche
  /// normalement dans la liste non filtree. Meme raisonnement que pour l'offre.
  String? _validatePositions(
    AppLocalizations l10n,
    List<FootballPosition>? positions,
  ) {
    if (positions == null || positions.isEmpty) {
      return l10n.eventFormPositionsRequiredValidator;
    }
    return null;
  }

  String? _validateTitle(AppLocalizations l10n, String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return l10n.eventFormTitleRequiredValidator;
    if (normalized.length > _maxTitleLength) {
      return l10n.eventFormTitleMaxLengthValidator(_maxTitleLength);
    }
    return null;
  }

  String? _validateDescription(AppLocalizations l10n, String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return l10n.eventFormDescriptionRequiredValidator;
    if (normalized.length < _minDescriptionLength) {
      return l10n.eventFormDescriptionMinLengthValidator(
        _minDescriptionLength,
      );
    }
    if (normalized.length > _maxDescriptionLength) {
      return l10n.eventFormDescriptionMaxLengthValidator(
        _maxDescriptionLength,
      );
    }
    return null;
  }

  String? _validateRequiredLocation(AppLocalizations l10n, String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return l10n.eventFormLocationRequiredValidator;
    return null;
  }

  String? _validateOptionalCapacity(AppLocalizations l10n, String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;
    final capacity = int.tryParse(normalized);
    if (capacity == null || capacity <= 0) {
      return l10n.eventFormPositiveNumberMessage;
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

    final l10n = AppLocalizations.of(context)!;
    final discard = await AdDialogs.confirm(
      context: context,
      title: l10n.eventFormDiscardConfirmTitle,
      message: l10n.eventFormDiscardConfirmMessage,
      confirmLabel: l10n.eventFormDiscardAction,
      cancelLabel: l10n.eventFormContinueEditingAction,
      danger: true,
    );
    if (discard && mounted) {
      Get.back();
    }
  }

  Widget _buildDatePicker(
    AppLocalizations l10n,
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
                  : l10n.eventFormChooseDateLabel,
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
    super.dispose();
  }
}
