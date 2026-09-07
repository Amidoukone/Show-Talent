import 'dart:async';
import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/event_detail_screen.dart';
import 'package:adfoot/screens/event_form_screen.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_owner_tag.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:adfoot/widgets/ad_system_notice.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:adfoot/theme/ad_tokens.dart';

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key, this.showAppBar = true});

  /// False when a host already provides the chrome. See [OffreScreen].
  final bool showAppBar;

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  final EventController eventController = Get.find<EventController>();
  final UserController userController = Get.find<UserController>();

  final TextEditingController _searchController = TextEditingController();

  String _selectedStatus = 'tous';
  String _selectedVisibility = 'tous';
  bool _onlyUpcoming = false;
  bool _onlyMine = false;

  /// Le poste demande, ou null pour « tous ».
  ///
  /// Le seul des trois criteres footballistiques qui parte au serveur, via
  /// `EventController.setPositionFilter`. Les deux autres se posent sur la
  /// page deja chargee : Firestore n'accepte qu'un seul champ tableau par
  /// index composite, et `ageCategories` en est un second.
  FootballPosition? _selectedPosition;

  /// La categorie d'age demandee, filtree sur la page.
  AgeCategory? _selectedCategory;

  /// Le niveau de structure demande, filtre sur la page.
  ClubLevel? _selectedLevel;

  /// Les evenements deja comptes pendant cette session d'ecran.
  ///
  /// `itemBuilder` rejoue a chaque rebuild -- defilement, filtre, snapshot --
  /// et sans ce garde le meme evenement partirait en transaction a chaque
  /// passage. La transaction le rattraperait via `viewedBy`, mais au prix
  /// d'une lecture Firestore par rebuild.
  final Set<String> _viewedEvents = <String>{};

  final Set<String> _pendingEventActions = <String>{};
  AdSystemNoticeData? _systemNotice;

  String _normalizeStatus(String rawStatus) {
    return Event.normalizeStatus(rawStatus);
  }

  bool _isClosedStatus(String rawStatus) {
    final status = _normalizeStatus(rawStatus);
    return status == 'ferme' || status == 'archive';
  }

  bool _isFull(Event event) {
    final capacity = event.capaciteMax;
    return capacity != null && event.participants.length >= capacity;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: widget.showAppBar
          ? AdAppBar(
              title: l10n.opportunitiesEventsTab,
              subtitle: l10n.eventSubtitle,
              showBottomDivider: true,
            )
          : null,
      body: Obx(() {
        final currentUser = userController.user;
        if (currentUser == null) {
          return _buildMissingUserState();
        }

        final allEvents = eventController.events;
        if (eventController.isLoading && allEvents.isEmpty) {
          return _buildSkeletons();
        }

        final events = _filterEvents(allEvents, currentUser);
        final canLoadMoreEvents = eventController.hasMoreEvents;

        // Un fil vide sous filtre serveur reste un fil filtre : la barre doit
        // rester a l'ecran, sinon l'utilisateur n'a aucun moyen de revenir --
        // et « aucun evenement » se lirait comme « il n'y en a pas », alors
        // qu'il n'y en a pas *a ce poste*.
        final hasServerFilter = _selectedPosition != null;

        if (allEvents.isEmpty && !hasServerFilter) {
          return Column(
            children: [
              _buildSystemNoticeSlot(),
              Expanded(
                child: _buildEmptyState(currentUser, filteredOut: false),
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildSystemNoticeSlot(),
            _buildFilters(currentUser),
            Expanded(
              child: events.isEmpty
                  ? _buildEmptyState(
                      currentUser,
                      filteredOut: true,
                      canLoadMore: canLoadMoreEvents,
                      isLoadingMore: eventController.isLoadingMore,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
                      itemCount: events.length + (canLoadMoreEvents ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == events.length) {
                          return _buildLoadMoreFooter();
                        }

                        final event = events[index];
                        final organiser = event.organisateur;
                        final isParticipant = event.participants.any(
                          (p) => p.uid == currentUser.uid,
                        );
                        final isOrganisateur = organiser.uid == currentUser.uid;

                        // Compte une impression dans la liste, comme le fait
                        // l'offre : les deux nombres doivent se comparer.
                        if (!isOrganisateur &&
                            !_viewedEvents.contains(event.id)) {
                          _viewedEvents.add(event.id);
                          unawaited(
                            eventController.incrementVues(
                              event: event,
                              viewer: currentUser,
                            ),
                          );
                        }

                        return Card(
                          color: AdColors.surfaceCard,
                          clipBehavior: Clip.antiAlias,
                          elevation: 0,
                          margin: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AdRadius.lg),
                            side: const BorderSide(color: AdColors.divider),
                          ),
                          child: InkWell(
                            onTap: () => _openEventDetails(event),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // L'affiche occupe toute la largeur, au-dessus
                                // du padding : c'est elle qu'on regarde en
                                // premier, et une marge autour la ferait lire
                                // comme une illustration secondaire.
                                if ((event.flyerUrl ?? '').trim().isNotEmpty)
                                  AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: Image.network(
                                      event.flyerUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stack) =>
                                              const SizedBox.shrink(),
                                    ),
                                  ),
                                Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: isOrganisateur
                                            ? AdOwnerTag(
                                                label: l10n.eventOwnerTag,
                                              )
                                            : AdCompactIdentityRow(
                                                user: organiser,
                                              ),
                                      ),
                                      const SizedBox(width: 8),
                                      _StatusBadge(status: event.statut),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    event.titre,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    event.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AdColors.onSurfaceMuted,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (eventController.isLoading)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 10),
                                      child: LinearProgressIndicator(
                                        minHeight: 2,
                                      ),
                                    ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _buildChip(
                                        Icons.place_outlined,
                                        event.lieu,
                                      ),
                                      // « Privé » promettait que l'evenement
                                      // etait cache : il ne l'a jamais ete.
                                      // La puce dit maintenant ce que le
                                      // reglage decrit vraiment -- comment
                                      // l'organisateur recrute -- et l'icone
                                      // suit : inscription, pas confidentialite.
                                      _buildChip(
                                        Icons.how_to_reg_outlined,
                                        event.estPublic
                                            ? l10n.eventOpenToAllLabel
                                            : l10n.eventBySelectionLabel,
                                      ),
                                      // Le poste avant le nombre d'inscrits :
                                      // c'est ce qu'un joueur cherche en
                                      // premier sur une detection.
                                      if (event.positionCodes.isNotEmpty)
                                        _buildChip(
                                          Icons.sports_soccer_outlined,
                                          event.positionCodes
                                              .map((p) => p.labelFr)
                                              .join(' · '),
                                        ),
                                      if (event.ageCategories.isNotEmpty)
                                        _buildChip(
                                          Icons.cake_outlined,
                                          event.ageCategories
                                              .map((c) => c.labelFr)
                                              .join(' · '),
                                        ),
                                      _buildChip(
                                        Icons.group_outlined,
                                        l10n.eventParticipantsCountLabel(
                                          event.participants.length,
                                        ),
                                      ),
                                      _buildChip(
                                        Icons.visibility_outlined,
                                        l10n.eventViewsCountLabel(
                                          event.views ?? 0,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _buildTimingRow(event),
                                  const SizedBox(height: 12),
                                  _buildActions(
                                    context: context,
                                    event: event,
                                    currentUser: currentUser,
                                    isParticipant: isParticipant,
                                    isOrganisateur: isOrganisateur,
                                  ),
                                ],
                              ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      }),
      // See OffreScreen: the host's Publier button owns creation.
      floatingActionButton: widget.showAppBar
          ? _buildFloatingActionButton(userController.user)
          : null,
    );
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _selectedStatus = 'tous';
      _selectedVisibility = 'tous';
      _onlyUpcoming = false;
      _onlyMine = false;
      _selectedPosition = null;
      _selectedCategory = null;
      _selectedLevel = null;
    });
    // Doit repartir jusqu'au serveur, sinon le fil reste filtre par un poste
    // que plus aucun menu n'affiche.
    eventController.setPositionFilter(const <FootballPosition>[]);
  }

  /// Applique le poste, le seul filtre servi par le serveur.
  void _setPositionFilter(FootballPosition? position) {
    setState(() => _selectedPosition = position);
    eventController.setPositionFilter(
      position == null
          ? const <FootballPosition>[]
          : <FootballPosition>[position],
    );
  }

  bool get _hasActiveFilters {
    return _searchController.text.trim().isNotEmpty ||
        _selectedStatus != 'tous' ||
        _selectedVisibility != 'tous' ||
        _onlyUpcoming ||
        _onlyMine ||
        _selectedPosition != null ||
        _selectedCategory != null ||
        _selectedLevel != null;
  }

  Future<void> _openCreateEventForm() async {
    final result = await Get.to(() => const EventFormScreen());
    _handleEventFormResult(result);
  }

  Future<void> _openEditEventForm(Event event) async {
    final result = await Get.to(() => EventFormScreen(event: event));
    _handleEventFormResult(result);
  }

  Future<void> _openEventDetails(Event event) async {
    final result = await Get.to(() => EventDetailsScreen(event: event));
    _handleEventFormResult(result);
  }

  void _handleEventFormResult(Object? result) {
    if (result == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;

    if (result is EventFormResult) {
      _showSystemNotice(
        title: result.title,
        message: result.message,
        tone: result.kind == 'info'
            ? AdSystemNoticeTone.info
            : AdSystemNoticeTone.success,
      );
      return;
    }

    if (result == true) {
      _showSystemNotice(
        title: l10n.eventSavedTitle,
        message: l10n.eventListUpdatedMessage,
      );
    }
  }

  void _showSystemNotice({
    required String title,
    required String message,
    AdSystemNoticeTone tone = AdSystemNoticeTone.success,
  }) {
    final resolvedTitle = title.trim();
    final resolvedMessage = message.trim();
    if (!mounted || resolvedMessage.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _systemNotice = AdSystemNoticeData(
        title: resolvedTitle.isEmpty
            ? l10n.commonActionConfirmedTitle
            : resolvedTitle,
        message: resolvedMessage,
        tone: tone,
      );
    });
  }

  void _dismissSystemNotice() {
    if (!mounted || _systemNotice == null) return;
    setState(() => _systemNotice = null);
  }

  String _eventActionKey(Event event, String action) => '${event.id}:$action';

  bool _isEventActionPending(Event event, String action) {
    return _pendingEventActions.contains(_eventActionKey(event, action));
  }

  Future<ActionResponse?> _runEventAction({
    required Event event,
    required String action,
    required Future<ActionResponse> Function() task,
  }) async {
    final key = _eventActionKey(event, action);
    if (_pendingEventActions.contains(key)) return null;

    if (mounted) {
      setState(() => _pendingEventActions.add(key));
    } else {
      _pendingEventActions.add(key);
    }

    try {
      return await task();
    } finally {
      if (mounted) {
        setState(() => _pendingEventActions.remove(key));
      } else {
        _pendingEventActions.remove(key);
      }
    }
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  int _daysUntilStart(Event event) {
    return _dateOnly(
      event.dateDebut,
    ).difference(_dateOnly(DateTime.now())).inDays;
  }

  int _daysUntilEnd(Event event) {
    return _dateOnly(
      event.dateFin,
    ).difference(_dateOnly(DateTime.now())).inDays;
  }

  bool _isExpired(Event event) => _daysUntilEnd(event) < 0;

  bool _isUpcomingSoon(Event event) {
    final days = _daysUntilStart(event);
    return days >= 0 && days <= 7;
  }

  bool _isOpenForRegistration(Event event) {
    return !_isClosedStatus(event.statut) && !_isExpired(event);
  }

  String _eventTimingSummary(Event event) {
    final l10n = AppLocalizations.of(context)!;
    if (_isExpired(event)) return l10n.eventFinishedLabel;
    final daysUntilStart = _daysUntilStart(event);
    if (daysUntilStart < 0) return l10n.eventOngoingLabel;
    if (daysUntilStart == 0) return l10n.eventTodayLabel;
    if (daysUntilStart == 1) return l10n.eventTomorrowLabel;
    if (daysUntilStart <= 7) return l10n.eventInDaysLabel(daysUntilStart);
    return l10n.eventUpcomingLabel;
  }

  List<Event> _filterEvents(List<Event> source, AppUser currentUser) {
    final query = _searchController.text.toLowerCase().trim();

    return source.where((event) {
      final matchesSearch =
          query.isEmpty ||
          event.titre.toLowerCase().contains(query) ||
          event.description.toLowerCase().contains(query) ||
          event.lieu.toLowerCase().contains(query) ||
          event.organisateur.nom.toLowerCase().contains(query) ||
          event.organisateur.role.toLowerCase().contains(query) ||
          (event.tags ?? const <String>[]).any(
            (tag) => tag.toLowerCase().contains(query),
          );

      final matchesStatus = _selectedStatus == 'tous'
          ? true
          : _normalizeStatus(event.statut) == _selectedStatus;

      final matchesVisibility = _selectedVisibility == 'tous'
          ? true
          : (_selectedVisibility == 'public'
                ? event.estPublic
                : !event.estPublic);

      final matchesUpcoming =
          !_onlyUpcoming || event.dateFin.isAfter(DateTime.now());
      final matchesMine =
          !_onlyMine || event.organisateur.uid == currentUser.uid;

      // Categorie et niveau se posent ici, sur la page deja bornee, et non au
      // serveur : un index composite Firestore n'accepte qu'un seul champ
      // tableau, et le poste occupe cette place.
      final matchesCategory = _selectedCategory == null ||
          event.ageCategories.contains(_selectedCategory);
      final matchesLevel =
          _selectedLevel == null || event.clubLevel == _selectedLevel;

      return matchesSearch &&
          matchesStatus &&
          matchesVisibility &&
          matchesUpcoming &&
          matchesMine &&
          matchesCategory &&
          matchesLevel;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Widget _buildMissingUserState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AdStatePanel(
          icon: Icons.person_off,
          title: l10n.eventSessionUnavailableTitle,
          message: l10n.eventProfileLoadFailedMessage,
          action: AdButton(
            expanded: false,
            label: l10n.eventBackToHomeAction,
            onPressed: () {
              Get.offAllNamed(AppRoutes.main, arguments: {'tab': 0});
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletons() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 3,
      itemBuilder: (_, _) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 16, width: 160, color: AdColors.surfaceCardAlt),
              const SizedBox(height: 10),
              Container(
                height: 14,
                width: double.infinity,
                color: AdColors.surfaceCardAlt,
              ),
              const SizedBox(height: 6),
              Container(
                height: 14,
                width: double.infinity,
                color: AdColors.surfaceCardAlt,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSystemNoticeSlot() {
    final notice = _systemNotice;

    return AnimatedSwitcher(
      duration: AdMotion.normal,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: notice == null
          ? const SizedBox.shrink(key: ValueKey<String>('event-notice-empty'))
          : Padding(
              key: ValueKey<String>(
                'event-notice-${notice.title}-${notice.message}',
              ),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: AdSystemNotice(
                notice: notice,
                onDismiss: _dismissSystemNotice,
              ),
            ),
    );
  }

  Widget _buildEmptyState(
    AppUser currentUser, {
    required bool filteredOut,
    bool canLoadMore = false,
    bool isLoadingMore = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isOrganizer = isOpportunityPublisherRole(currentUser.role);
    final shouldLoadMore = filteredOut && canLoadMore;
    final actionLabel = shouldLoadMore
        ? isLoadingMore
              ? l10n.offreLoadingEllipsis
              : l10n.eventLoadMoreButton
        : filteredOut
        ? l10n.offreResetFiltersAction
        : isOrganizer
        ? l10n.eventCreateAction
        : l10n.offreExploreVideosAction;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AdStatePanel(
          icon: Icons.event_busy,
          title: filteredOut
              ? l10n.offreNoResultsTitle
              : l10n.eventNoneAvailableTitle,
          message: filteredOut
              ? l10n.eventNoResultsMessage
              : isOrganizer
              ? l10n.eventNoneAvailablePublisherMessage
              : l10n.offreNoneAvailableViewerMessage,
          action: AdButton(
            expanded: false,
            label: actionLabel,
            loading: shouldLoadMore && isLoadingMore,
            leading: shouldLoadMore ? Icons.expand_more_rounded : null,
            onPressed: isLoadingMore
                ? null
                : () {
                    if (shouldLoadMore) {
                      eventController.loadMoreEvents();
                      return;
                    }

                    if (filteredOut) {
                      _resetFilters();
                      return;
                    }

                    if (isOrganizer) {
                      _openCreateEventForm();
                      return;
                    }

                    Get.offAllNamed(AppRoutes.main, arguments: {'tab': 0});
                  },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadMoreFooter() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
        child: AdButton(
          expanded: false,
          kind: AdButtonKind.outline,
          size: AdButtonSize.compact,
          leading: Icons.expand_more_rounded,
          loading: eventController.isLoadingMore,
          label: eventController.isLoadingMore
              ? l10n.offreLoadingEllipsis
              : l10n.eventLoadMoreButton,
          onPressed: eventController.isLoadingMore
              ? null
              : () {
                  eventController.loadMoreEvents();
                },
        ),
      ),
    );
  }

  Widget _buildFilters(AppUser currentUser) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        color: AdColors.surfaceAlt,
        border: Border(bottom: BorderSide(color: AdColors.divider)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: l10n.eventSearchHint,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  prefixIcon: const Icon(Icons.search),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 42,
                    minHeight: 42,
                  ),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.offreClearSearchTooltip,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                ),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: l10n.eventFilterAllLabel,
                      selected: _selectedStatus == 'tous',
                      onTap: () => setState(() => _selectedStatus = 'tous'),
                    ),
                    _FilterChip(
                      label: l10n.eventFilterOpenLabel,
                      selected: _selectedStatus == 'ouvert',
                      onTap: () => setState(() => _selectedStatus = 'ouvert'),
                    ),
                    _FilterChip(
                      label: l10n.eventFilterClosedLabel,
                      selected: _selectedStatus == 'ferme',
                      onTap: () => setState(() => _selectedStatus = 'ferme'),
                    ),
                    _FilterChip(
                      label: l10n.eventFilterArchivedLabel,
                      selected: _selectedStatus == 'archive',
                      onTap: () => setState(() => _selectedStatus = 'archive'),
                    ),
                    const SizedBox(width: 8),
                    // Les valeurs restent `public` / `prive` : elles sont
                    // stockees et lues par le portail admin. Seuls les
                    // libelles changent, pour ne plus laisser croire que le
                    // second filtre revele des evenements caches -- il n'y en
                    // a pas, ils sont tous lisibles par tout compte actif.
                    _FilterChip(
                      label: l10n.eventFilterOpenToAllLabel,
                      selected: _selectedVisibility == 'public',
                      onTap: () =>
                          setState(() => _selectedVisibility = 'public'),
                    ),
                    _FilterChip(
                      label: l10n.eventBySelectionLabel,
                      selected: _selectedVisibility == 'prive',
                      onTap: () =>
                          setState(() => _selectedVisibility = 'prive'),
                    ),
                    _FilterChip(
                      label: l10n.eventUpcomingLabel,
                      selected: _onlyUpcoming,
                      onTap: () =>
                          setState(() => _onlyUpcoming = !_onlyUpcoming),
                    ),
                    if (isOpportunityPublisherRole(currentUser.role)) ...[
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: l10n.eventFilterMineLabel,
                        selected: _onlyMine,
                        onTap: () => setState(() => _onlyMine = !_onlyMine),
                      ),
                    ],
                    const SizedBox(width: 12),
                    // Poste, categorie et niveau : le vocabulaire que
                    // l'evenement porte desormais, et sans lequel l'onglet ne
                    // savait trier que par une recherche plein texte.
                    _buildFilterDropdown<FootballPosition>(
                      value: _selectedPosition,
                      allLabel: l10n.offreAllPositionsLabel,
                      values: FootballPosition.values,
                      labelOf: (position) => position.labelFr,
                      onChanged: _setPositionFilter,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterDropdown<AgeCategory>(
                      value: _selectedCategory,
                      allLabel: l10n.offreAllCategoriesLabel,
                      values: AgeCategory.values,
                      labelOf: (category) => category.labelFr,
                      onChanged: (value) =>
                          setState(() => _selectedCategory = value),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterDropdown<ClubLevel>(
                      value: _selectedLevel,
                      allLabel: l10n.offreAllLevelsLabel,
                      values: ClubLevel.values,
                      labelOf: (level) => level.labelFr,
                      onChanged: (value) =>
                          setState(() => _selectedLevel = value),
                    ),
                    if (_hasActiveFilters)
                      TextButton.icon(
                        onPressed: _resetFilters,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: Text(l10n.commonReset),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownShell({required Widget child}) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdColors.divider),
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }

  /// Un menu « tous, ou une valeur » sur un vocabulaire footballistique.
  ///
  /// Les libelles, jamais les codes : personne ne choisit « LB » dans une
  /// liste. Le pendant exact de celui de `OffreScreen`.
  Widget _buildFilterDropdown<T extends Object>({
    required T? value,
    required String allLabel,
    required List<T> values,
    required String Function(T value) labelOf,
    required ValueChanged<T?> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;

    return _buildDropdownShell(
      child: DropdownButton<T?>(
        value: value,
        underline: const SizedBox.shrink(),
        dropdownColor: AdColors.surfaceCard,
        style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
        items: <DropdownMenuItem<T?>>[
          DropdownMenuItem<T?>(value: null, child: Text(allLabel)),
          for (final entry in values)
            DropdownMenuItem<T?>(value: entry, child: Text(labelOf(entry))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildChip(IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;

    return Chip(
      avatar: Icon(icon, size: 16, color: cs.primary),
      label: Text(label, style: TextStyle(color: cs.onSurface)),
      backgroundColor: AdColors.surfaceCard,
      side: const BorderSide(color: AdColors.divider),
    );
  }

  Widget _buildTimingRow(Event event) {
    final l10n = AppLocalizations.of(context)!;
    final expired = _isExpired(event);
    final soon = _isUpcomingSoon(event);
    final color = expired
        ? AdColors.error
        : soon
        ? AdColors.warning
        : AdColors.onSurfaceMuted;

    return Row(
      children: [
        Icon(
          expired ? Icons.timer_off_outlined : Icons.event,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            l10n.offreDateSummaryLabel(
              l10n.eventDateRangeLabel(
                DateFormat('dd MMM yyyy').format(event.dateDebut),
                DateFormat('dd MMM yyyy').format(event.dateFin),
              ),
              _eventTimingSummary(event),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: expired || soon ? FontWeight.w700 : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions({
    required BuildContext context,
    required Event event,
    required AppUser currentUser,
    required bool isParticipant,
    required bool isOrganisateur,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isClosed = !_isOpenForRegistration(event);
    final isFull = _isFull(event);
    final registerPending = _isEventActionPending(event, 'registration');
    final statusPending = _isEventActionPending(event, 'status');
    final deletePending = _isEventActionPending(event, 'delete');

    if (isOrganisateur) {
      final statusValue = _normalizeStatus(event.statut);

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            value: statusValue,
            underline: const SizedBox.shrink(),
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
            onChanged: statusPending
                ? null
                : (value) async {
                    if (value == null || value == statusValue) return;

                    final updated = Event(
                      id: event.id,
                      titre: event.titre,
                      description: event.description,
                      dateDebut: event.dateDebut,
                      dateFin: event.dateFin,
                      organisateur: event.organisateur,
                      participants: event.participants,
                      statut: value,
                      lieu: event.lieu,
                      estPublic: event.estPublic,
                      createdAt: event.createdAt,
                      capaciteMax: event.capaciteMax,
                      // Meme motif que l'affiche : cette reconstruction
                      // enumere les champs, donc un oubli ici effacerait le
                      // vocabulaire a chaque changement de statut.
                      positionCodes: event.positionCodes,
                      ageCategories: event.ageCategories,
                      clubLevel: event.clubLevel,
                      tags: event.tags,
                      streamingUrl: null,
                      // Meme defaut que le formulaire d'edition avant 61e2e54 : `updateEvent`
                      // traduit un null par `FieldValue.delete()`, donc changer le statut
                      // depuis la liste effacait l'affiche de l'evenement.
                      flyerUrl: event.flyerUrl,
                      views: event.views,
                      viewedBy: event.viewedBy,
                      archivedAt: value == 'archive'
                          ? DateTime.now()
                          : event.archivedAt,
                      lastUpdated: DateTime.now(),
                    );

                    final response = await _runEventAction(
                      event: event,
                      action: 'status',
                      task: () =>
                          eventController.updateEvent(updated, currentUser),
                    );
                    if (response != null) {
                      _showResponse(
                        response,
                        successTitle: l10n.offreStatusUpdatedTitle,
                      );
                    }
                  },
          ),
          if (statusPending)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (deletePending)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            PopupMenuButton<String>(
              tooltip: l10n.offreMoreActionsTooltip,
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AdColors.onSurfaceMuted,
              ),
              color: AdColors.surfaceCard,
              onSelected: (value) {
                if (value == 'edit') {
                  _openEditEventForm(event);
                } else if (value == 'delete') {
                  _confirmDeleteEvent(context, event);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 18),
                      const SizedBox(width: 10),
                      Text(l10n.offreEditAction),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: AdColors.error,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.settingsDeleteAction,
                        style: const TextStyle(color: AdColors.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      );
    }

    if (!isParticipant && isClosed) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AdButton(
          onPressed:
              (!isParticipant && !isClosed && !isFull && !registerPending)
              ? () async {
                  final response = await _runEventAction(
                    event: event,
                    action: 'registration',
                    task: () =>
                        eventController.registerToEvent(event.id, currentUser),
                  );
                  if (response != null) {
                    _showResponse(
                      response,
                      successTitle: l10n.eventRegistrationConfirmedTitle,
                    );
                  }
                }
              : null,
          loading: registerPending,
          leading: Icons.event_available,
          label: registerPending
              ? l10n.eventRegisteringEllipsis
              : isFull
              ? l10n.eventFullLabel
              : l10n.eventRegisterButton,
          size: AdButtonSize.compact,
          expanded: false,
        ),
        if (isParticipant && !isClosed)
          AdButton(
            onPressed: registerPending
                ? null
                : () => _confirmUnregisterEvent(context, event, currentUser),
            leading: Icons.person_remove_outlined,
            label: l10n.eventUnregisterButton,
            kind: AdButtonKind.outline,
            size: AdButtonSize.compact,
            expanded: false,
          ),
      ],
    );
  }

  FloatingActionButton? _buildFloatingActionButton(AppUser? currentUser) {
    if (currentUser != null && isOpportunityPublisherRole(currentUser.role)) {
      return FloatingActionButton(
        onPressed: () {
          _openCreateEventForm();
        },
        backgroundColor: AdColors.brand,
        foregroundColor: AdColors.brandOn,
        child: const Icon(Icons.add),
      );
    }
    return null;
  }

  Future<void> _confirmDeleteEvent(BuildContext context, Event event) async {
    if (_isEventActionPending(event, 'delete')) return;
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await AdDialogs.confirm(
      context: context,
      title: l10n.eventConfirmDeleteTitle,
      message: l10n.eventConfirmDeleteMessage,
      confirmLabel: l10n.settingsDeleteAction,
      cancelLabel: l10n.commonCancel,
      danger: true,
    );
    if (!confirmed) return;

    final currentUser = userController.user;
    if (currentUser == null) {
      AdFeedback.error(
        l10n.profileActionErrorTitle,
        l10n.commonUserNotFoundMessage,
      );
      return;
    }

    final response = await _runEventAction(
      event: event,
      action: 'delete',
      task: () => eventController.deleteEvent(event.id, currentUser),
    );
    if (response != null) {
      _showResponse(response, successTitle: l10n.eventDeletedTitle);
    }
  }

  Future<void> _confirmUnregisterEvent(
    BuildContext context,
    Event event,
    AppUser currentUser,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AdDialogs.confirm(
      context: context,
      title: l10n.eventUnregisterButton,
      message: l10n.eventConfirmUnregisterMessage,
      confirmLabel: l10n.eventConfirmAction,
      cancelLabel: l10n.commonCancel,
      danger: true,
    );
    if (!confirmed) return;

    final response = await _runEventAction(
      event: event,
      action: 'registration',
      task: () => eventController.unregisterFromEvent(event.id, currentUser),
    );
    if (response != null) {
      _showResponse(response, successTitle: l10n.eventRegistrationWithdrawnTitle);
    }
  }

  void _showResponse(ActionResponse response, {required String successTitle}) {
    if (response.toast == ToastLevel.none) {
      return;
    }

    if (response.success) {
      _showSystemNotice(title: successTitle, message: response.message);
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    if (response.toast == ToastLevel.info) {
      AdFeedback.info(l10n.commonInfoTitle, response.message);
      return;
    }

    AdFeedback.error(l10n.profileActionErrorTitle, response.message);
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  String _labelFor(AppLocalizations l10n, String normalized) {
    switch (normalized) {
      case 'ouvert':
        return l10n.eventStatusOpenLabel;
      case 'ferme':
        return l10n.eventStatusClosedLabel;
      case 'archive':
        return l10n.eventStatusArchivedLabel;
      case 'brouillon':
        return l10n.eventStatusDraftLabel;
      default:
        return normalized;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    Color bg;
    Color fg;

    final normalized = Event.normalizeStatus(status);

    switch (normalized) {
      case 'ouvert':
        bg = cs.primary.withValues(alpha: 0.15);
        fg = cs.primary;
        break;
      case 'ferme':
        bg = AdColors.error.withValues(alpha: 0.15);
        fg = AdColors.error;
        break;
      case 'archive':
        bg = AdColors.onSurfaceMuted.withValues(alpha: 0.15);
        fg = AdColors.onSurfaceMuted;
        break;
      case 'brouillon':
        bg = AdColors.warning.withValues(alpha: 0.18);
        fg = AdColors.warning;
        break;
      default:
        bg = cs.secondary.withValues(alpha: 0.15);
        fg = cs.secondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: const BorderSide(color: AdColors.divider).toBorder(),
      ),
      child: Text(
        _labelFor(l10n, normalized),
        style: TextStyle(fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        selectedColor: cs.primary.withValues(alpha: 0.18),
        backgroundColor: AdColors.surfaceCard,
        labelStyle: TextStyle(
          color: selected ? cs.primary : cs.onSurface,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
        side: const BorderSide(color: AdColors.divider),
      ),
    );
  }
}

extension _BorderSideX on BorderSide {
  Border toBorder() => Border.fromBorderSide(this);
}
