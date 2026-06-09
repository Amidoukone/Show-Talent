import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/event_detail_screen.dart';
import 'package:adfoot/screens/event_form_screen.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:adfoot/widgets/ad_system_notice.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:adfoot/theme/ad_tokens.dart';

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key});

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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const AdAppBar(
        title: 'Événements',
        subtitle: 'Opportunités et rencontres',
        showBottomDivider: true,
      ),
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

        if (allEvents.isEmpty) {
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
            _buildEventsOverview(allEvents, events, currentUser),
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
                      padding: const EdgeInsets.all(8),
                      itemCount: events.length + (canLoadMoreEvents ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == events.length) {
                          return _buildLoadMoreFooter();
                        }

                        final event = events[index];
                        final organiser = event.organisateur;
                        final isParticipant = event.participants
                            .any((p) => p.uid == currentUser.uid);
                        final isOrganisateur = organiser.uid == currentUser.uid;

                        return Card(
                          color: AdColors.surfaceCard,
                          clipBehavior: Clip.antiAlias,
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: AdColors.divider),
                          ),
                          child: InkWell(
                            onTap: () => _openEventDetails(event),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildOrganiserSection(organiser),
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              event.titre,
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                color: cs.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              event.description,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: AdColors.onSurfaceMuted,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _StatusBadge(status: event.statut),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (eventController.isLoading)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child:
                                          LinearProgressIndicator(minHeight: 2),
                                    ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _buildChip(
                                        Icons.calendar_today,
                                        '${DateFormat('dd MMM').format(event.dateDebut)} -> ${DateFormat('dd MMM').format(event.dateFin)}',
                                      ),
                                      _buildChip(
                                          Icons.place_outlined, event.lieu),
                                      _buildChip(
                                        Icons.privacy_tip_outlined,
                                        event.estPublic ? 'Public' : 'Privé',
                                      ),
                                      _buildChip(
                                        Icons.group_outlined,
                                        '${event.participants.length} participants',
                                      ),
                                      if (_isExpired(event))
                                        _buildAlertChip(
                                          Icons.timer_off_outlined,
                                          'Terminé',
                                          AdColors.error,
                                        )
                                      else if (_isUpcomingSoon(event))
                                        _buildAlertChip(
                                          Icons.schedule_rounded,
                                          _eventTimingSummary(event),
                                          AdColors.warning,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _buildTimingRow(event),
                                  const SizedBox(height: 16),
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
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      }),
      floatingActionButton: _buildFloatingActionButton(userController.user),
    );
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _selectedStatus = 'tous';
      _selectedVisibility = 'tous';
      _onlyUpcoming = false;
      _onlyMine = false;
    });
  }

  bool get _hasActiveFilters {
    return _searchController.text.trim().isNotEmpty ||
        _selectedStatus != 'tous' ||
        _selectedVisibility != 'tous' ||
        _onlyUpcoming ||
        _onlyMine;
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
        title: 'Événement enregistré',
        message: 'La liste des événements a été mise à jour.',
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

    setState(() {
      _systemNotice = AdSystemNoticeData(
        title: resolvedTitle.isEmpty ? 'Action confirmée' : resolvedTitle,
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
    return _dateOnly(event.dateDebut)
        .difference(_dateOnly(DateTime.now()))
        .inDays;
  }

  int _daysUntilEnd(Event event) {
    return _dateOnly(event.dateFin)
        .difference(_dateOnly(DateTime.now()))
        .inDays;
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
    if (_isExpired(event)) return 'Terminé';
    final daysUntilStart = _daysUntilStart(event);
    if (daysUntilStart < 0) return 'En cours';
    if (daysUntilStart == 0) return 'Aujourd’hui';
    if (daysUntilStart == 1) return 'Demain';
    if (daysUntilStart <= 7) return 'Dans $daysUntilStart jours';
    return 'À venir';
  }

  List<Event> _filterEvents(List<Event> source, AppUser currentUser) {
    final query = _searchController.text.toLowerCase().trim();

    return source.where((event) {
      final matchesSearch = query.isEmpty ||
          event.titre.toLowerCase().contains(query) ||
          event.description.toLowerCase().contains(query) ||
          event.lieu.toLowerCase().contains(query) ||
          event.organisateur.nom.toLowerCase().contains(query) ||
          event.organisateur.role.toLowerCase().contains(query) ||
          (event.tags ?? const <String>[])
              .any((tag) => tag.toLowerCase().contains(query));

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

      return matchesSearch &&
          matchesStatus &&
          matchesVisibility &&
          matchesUpcoming &&
          matchesMine;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Widget _buildMissingUserState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AdStatePanel(
          icon: Icons.person_off,
          title: 'Session indisponible',
          message: 'Impossible de charger le profil utilisateur.',
          action: AdButton(
            expanded: false,
            label: 'Revenir à l’accueil',
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
      itemBuilder: (_, __) => Card(
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

  Widget _buildEventsOverview(
    List<Event> allEvents,
    List<Event> filteredEvents,
    AppUser currentUser,
  ) {
    final isPublisher = isOpportunityPublisherRole(currentUser.role);
    final openCount =
        allEvents.where((event) => _isOpenForRegistration(event)).length;
    final soonCount = allEvents.where((event) => _isUpcomingSoon(event)).length;
    final ownedEvents =
        allEvents.where((event) => event.organisateur.uid == currentUser.uid);
    final myParticipants = ownedEvents.fold<int>(
      0,
      (total, event) => total + event.participants.length,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        color: AdColors.surface,
        border: Border(bottom: BorderSide(color: AdColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AdColors.brand.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AdRadius.md),
                  border: Border.all(
                    color: AdColors.brand.withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.event_available_outlined,
                  color: AdColors.brand,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Événements',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AdColors.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isPublisher
                          ? 'Gérez vos événements et les inscriptions.'
                          : 'Repérez les événements ouverts et à venir.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AdColors.onSurfaceMuted,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _EventMetric(
                icon: Icons.filter_list_rounded,
                label: 'Affichés',
                value: '${filteredEvents.length}/${allEvents.length}',
              ),
              _EventMetric(
                icon: Icons.event_available_outlined,
                label: 'Ouverts',
                value: '$openCount',
              ),
              _EventMetric(
                icon: Icons.schedule_rounded,
                label: 'Bientôt',
                value: '$soonCount',
              ),
              if (isPublisher)
                _EventMetric(
                  icon: Icons.mark_email_unread_outlined,
                  label: 'Inscrits reçus',
                  value: '$myParticipants',
                ),
            ],
          ),
          if (isPublisher) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AdButton(
                  onPressed: () => setState(() => _onlyMine = !_onlyMine),
                  leading: _onlyMine
                      ? Icons.public_rounded
                      : Icons.manage_accounts_outlined,
                  label: _onlyMine ? 'Tous les événements' : 'Mes événements',
                  kind: AdButtonKind.outline,
                  size: AdButtonSize.compact,
                  expanded: false,
                ),
                AdButton(
                  onPressed: () {
                    _openCreateEventForm();
                  },
                  leading: Icons.add_rounded,
                  label: 'Créer un événement',
                  size: AdButtonSize.compact,
                  expanded: false,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    AppUser currentUser, {
    required bool filteredOut,
    bool canLoadMore = false,
    bool isLoadingMore = false,
  }) {
    final isOrganizer = isOpportunityPublisherRole(currentUser.role);
    final shouldLoadMore = filteredOut && canLoadMore;
    final actionLabel = shouldLoadMore
        ? isLoadingMore
            ? 'Chargement...'
            : 'Charger plus d’événements'
        : filteredOut
            ? 'Réinitialiser les filtres'
            : isOrganizer
                ? 'Créer un événement'
                : 'Explorer les vidéos';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AdStatePanel(
          icon: Icons.event_busy,
          title: filteredOut ? 'Aucun résultat' : 'Aucun événement disponible',
          message: filteredOut
              ? 'Aucun événement ne correspond à vos filtres.'
              : isOrganizer
                  ? 'Vous pouvez publier votre premier événement.'
                  : 'Revenez plus tard ou explorez les vidéos de talents.',
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

                    Get.offAllNamed(
                      AppRoutes.main,
                      arguments: {'tab': 0},
                    );
                  },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadMoreFooter() {
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
              ? 'Chargement...'
              : 'Charger plus d’événements',
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
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: const BoxDecoration(
        color: AdColors.surfaceAlt,
        border: Border(
          bottom: BorderSide(color: AdColors.divider),
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Rechercher titre, lieu, organisateur...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer la recherche',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'Tous',
                  selected: _selectedStatus == 'tous',
                  onTap: () => setState(() => _selectedStatus = 'tous'),
                ),
                _FilterChip(
                  label: 'Ouverts',
                  selected: _selectedStatus == 'ouvert',
                  onTap: () => setState(() => _selectedStatus = 'ouvert'),
                ),
                _FilterChip(
                  label: 'Fermés',
                  selected: _selectedStatus == 'ferme',
                  onTap: () => setState(() => _selectedStatus = 'ferme'),
                ),
                _FilterChip(
                  label: 'Archivés',
                  selected: _selectedStatus == 'archive',
                  onTap: () => setState(() => _selectedStatus = 'archive'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Public',
                  selected: _selectedVisibility == 'public',
                  onTap: () => setState(() => _selectedVisibility = 'public'),
                ),
                _FilterChip(
                  label: 'Privé',
                  selected: _selectedVisibility == 'prive',
                  onTap: () => setState(() => _selectedVisibility = 'prive'),
                ),
                _FilterChip(
                  label: 'À venir',
                  selected: _onlyUpcoming,
                  onTap: () => setState(() => _onlyUpcoming = !_onlyUpcoming),
                ),
                if (isOpportunityPublisherRole(currentUser.role)) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Mes événements',
                    selected: _onlyMine,
                    onTap: () => setState(() => _onlyMine = !_onlyMine),
                  ),
                ],
                if (_hasActiveFilters)
                  TextButton.icon(
                    onPressed: _resetFilters,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Réinitialiser'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrganiserSection(AppUser organiser) {
    final hasPhoto = organiser.photoProfil.trim().startsWith('http');

    return Row(
      children: [
        GestureDetector(
          onTap: () =>
              Get.to(() => ProfileScreen(uid: organiser.uid, isReadOnly: true)),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: AdColors.surfaceCardAlt,
            backgroundImage:
                hasPhoto ? NetworkImage(organiser.photoProfil) : null,
            child: hasPhoto
                ? null
                : const Icon(Icons.person, color: Colors.white70),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                organiser.nom,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                organiser.role,
                style: const TextStyle(
                  color: AdColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
      ],
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

  Widget _buildAlertChip(IconData icon, String label, Color color) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }

  Widget _buildTimingRow(Event event) {
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
            '${DateFormat('dd MMM yyyy').format(event.dateDebut)} -> ${DateFormat('dd MMM yyyy').format(event.dateFin)} · ${_eventTimingSummary(event)}',
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
            items: const [
              DropdownMenuItem(value: 'brouillon', child: Text('Brouillon')),
              DropdownMenuItem(value: 'ouvert', child: Text('Ouvert')),
              DropdownMenuItem(value: 'ferme', child: Text('Fermé')),
              DropdownMenuItem(value: 'archive', child: Text('Archivé')),
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
                      tags: event.tags,
                      streamingUrl: null,
                      flyerUrl: null,
                      views: event.views,
                      archivedAt: value == 'archive'
                          ? DateTime.now()
                          : event.archivedAt,
                      lastUpdated: DateTime.now(),
                    );

                    final response = await _runEventAction(
                      event: event,
                      action: 'status',
                      task: () => eventController.updateEvent(
                        updated,
                        currentUser,
                      ),
                    );
                    if (response != null) {
                      _showResponse(response,
                          successTitle: 'Statut mis à jour');
                    }
                  },
          ),
          if (statusPending)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          TextButton.icon(
            onPressed: () => _openEditEventForm(event),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Modifier'),
          ),
          TextButton.icon(
            onPressed: () => _openEventDetails(event),
            icon: const Icon(Icons.info_outline),
            label: const Text('Détails'),
          ),
          TextButton.icon(
            onPressed: deletePending
                ? null
                : () => _confirmDeleteEvent(context, event),
            icon: deletePending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline, color: Colors.red),
            label: Text(deletePending ? 'Suppression...' : 'Supprimer'),
          ),
        ],
      );
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
                        task: () => eventController.registerToEvent(
                          event.id,
                          currentUser,
                        ),
                      );
                      if (response != null) {
                        _showResponse(
                          response,
                          successTitle: 'Inscription confirmée',
                        );
                      }
                    }
                  : null,
          loading: registerPending,
          leading: Icons.event_available,
          label: registerPending
              ? 'Inscription...'
              : isClosed
                  ? 'Événement fermé'
                  : isFull
                      ? 'Complet'
                      : 'S’inscrire',
          size: AdButtonSize.compact,
          expanded: false,
        ),
        if (isParticipant && !isClosed)
          AdButton(
            onPressed: registerPending
                ? null
                : () => _confirmUnregisterEvent(context, event, currentUser),
            leading: Icons.person_remove_outlined,
            label: 'Se désinscrire',
            kind: AdButtonKind.outline,
            size: AdButtonSize.compact,
            expanded: false,
          )
        else
          AdButton(
            onPressed: () => _openEventDetails(event),
            leading: Icons.info_outline,
            label: 'Détails',
            kind: AdButtonKind.tonal,
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

    final confirmed = await AdDialogs.confirm(
      context: context,
      title: 'Supprimer',
      message: 'Voulez-vous vraiment supprimer cet événement ?',
      confirmLabel: 'Supprimer',
      cancelLabel: 'Annuler',
      danger: true,
    );
    if (!confirmed) return;

    final currentUser = userController.user;
    if (currentUser == null) {
      AdFeedback.error('Erreur', 'Utilisateur introuvable.');
      return;
    }

    final response = await _runEventAction(
      event: event,
      action: 'delete',
      task: () => eventController.deleteEvent(event.id, currentUser),
    );
    if (response != null) {
      _showResponse(response, successTitle: 'Événement supprimé');
    }
  }

  Future<void> _confirmUnregisterEvent(
    BuildContext context,
    Event event,
    AppUser currentUser,
  ) async {
    final confirmed = await AdDialogs.confirm(
      context: context,
      title: 'Se désinscrire',
      message: 'Voulez-vous vraiment vous désinscrire de cet événement ?',
      confirmLabel: 'Confirmer',
      cancelLabel: 'Annuler',
      danger: true,
    );
    if (!confirmed) return;

    final response = await _runEventAction(
      event: event,
      action: 'registration',
      task: () => eventController.unregisterFromEvent(event.id, currentUser),
    );
    if (response != null) {
      _showResponse(response, successTitle: 'Inscription retirée');
    }
  }

  void _showResponse(
    ActionResponse response, {
    required String successTitle,
  }) {
    if (response.toast == ToastLevel.none) {
      return;
    }

    if (response.success) {
      _showSystemNotice(
        title: successTitle,
        message: response.message,
      );
      return;
    }

    if (response.toast == ToastLevel.info) {
      AdFeedback.info('Information', response.message);
      return;
    }

    AdFeedback.error('Erreur', response.message);
  }
}

class _EventMetric extends StatelessWidget {
  const _EventMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 38),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(AdRadius.md),
        border: Border.all(color: AdColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AdColors.brand),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: AdColors.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AdColors.onSurfaceMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  String _labelFor(String normalized) {
    switch (normalized) {
      case 'ouvert':
        return 'Ouvert';
      case 'ferme':
        return 'Fermé';
      case 'archive':
        return 'Archivé';
      case 'brouillon':
        return 'Brouillon';
      default:
        return normalized;
    }
  }

  @override
  Widget build(BuildContext context) {
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
        _labelFor(normalized),
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
