import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/event_detail_screen.dart';
import 'package:adfoot/screens/event_form_screen.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:adfoot/theme/ad_colors.dart';

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  final EventController eventController = Get.put(EventController());
  final UserController userController = Get.find<UserController>();
  final ChatController chatController = Get.isRegistered<ChatController>()
      ? Get.find()
      : Get.put(ChatController());

  final TextEditingController _searchController = TextEditingController();

  String _selectedStatus = 'tous';
  String _selectedVisibility = 'tous';
  bool _onlyUpcoming = true;

  final Map<String, bool> _pendingInscription = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppUser currentUser = userController.user!;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Événements',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        centerTitle: true,
      ),
      body: Obx(() {
        if (eventController.isLoading) {
          return _buildSkeletons();
        }

        final events = _filterEvents(eventController.events);

        if (events.isEmpty) {
          return _buildEmptyState(currentUser);
        }

        return Column(
          children: [
            _buildFilters(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  final organiser = event.organisateur;
                  final isParticipant =
                      event.participants.any((p) => p.uid == currentUser.uid);
                  final isOrganisateur = organiser.uid == currentUser.uid;

                  return Card(
                    elevation: 5,
                    margin:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildOrganiserSection(organiser),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildChip(
                                Icons.calendar_today,
                                '${DateFormat('dd MMM').format(event.dateDebut)} → ${DateFormat('dd MMM').format(event.dateFin)}',
                              ),
                              _buildChip(Icons.place_outlined, event.lieu),
                              _buildChip(
                                Icons.privacy_tip_outlined,
                                event.estPublic ? 'Public' : 'Privé',
                              ),
                              _buildChip(
                                Icons.group_outlined,
                                '${event.participants.length} participants',
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildActions(
                            context: context,
                            event: event,
                            organiser: organiser,
                            currentUser: currentUser,
                            isParticipant: isParticipant,
                            isOrganisateur: isOrganisateur,
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
      floatingActionButton: _buildFloatingActionButton(currentUser),
    );
  }

  // =========================================================
  // 🔍 FILTRAGE
  // =========================================================

  List<Event> _filterEvents(List<Event> source) {
    final query = _searchController.text.toLowerCase().trim();

    return source.where((event) {
      final matchesSearch = query.isEmpty ||
          event.titre.toLowerCase().contains(query) ||
          event.lieu.toLowerCase().contains(query);

      final matchesStatus =
          _selectedStatus == 'tous' ? true : event.statut == _selectedStatus;

      final matchesVisibility = _selectedVisibility == 'tous'
          ? true
          : (_selectedVisibility == 'public'
              ? event.estPublic
              : !event.estPublic);

      final matchesUpcoming =
          !_onlyUpcoming ? true : event.dateFin.isAfter(DateTime.now());

      return matchesSearch &&
          matchesStatus &&
          matchesVisibility &&
          matchesUpcoming;
    }).toList()
      ..sort((a, b) => a.dateDebut.compareTo(b.dateDebut));
  }
  // =========================================================
  // 🧱 UI BUILDERS
  // =========================================================

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
                  color: AdColors.surfaceCardAlt),
              const SizedBox(height: 6),
              Container(
                  height: 14,
                  width: double.infinity,
                  color: AdColors.surfaceCardAlt),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppUser currentUser) {
    final isOrganizer =
        currentUser.role == 'club' || currentUser.role == 'recruteur';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.event_busy,
                size: 72, color: AdColors.onSurfaceMuted),
            const SizedBox(height: 12),
            const Text(
              'Aucun événement disponible',
              style: TextStyle(
                fontSize: 18,
                color: AdColors.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: isOrganizer
                  ? () => Get.to(() => const EventFormScreen())
                  : () => Get.offAllNamed('/main', arguments: {'tab': 2}),
              icon: Icon(isOrganizer ? Icons.add : Icons.groups),
              label: Text(
                isOrganizer ? 'Créer un événement' : 'Voir les clubs',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
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
            decoration: const InputDecoration(
              hintText: 'Rechercher (titre, lieu)…',
              prefixIcon: Icon(Icons.search),
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
                  selected: _selectedStatus == 'fermé',
                  onTap: () => setState(() => _selectedStatus = 'fermé'),
                ),
                _FilterChip(
                  label: 'Archivés',
                  selected: _selectedStatus == 'archivé',
                  onTap: () => setState(() => _selectedStatus = 'archivé'),
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

  // =========================================================
  // 🎯 ACTIONS (⚠️ MANQUANT AVANT – CORRIGÉ ICI)
  // =========================================================

  Widget _buildActions({
    required BuildContext context,
    required Event event,
    required AppUser organiser,
    required AppUser currentUser,
    required bool isParticipant,
    required bool isOrganisateur,
  }) {
    final isClosed = event.statut == 'fermé' || event.statut == 'archivé';
    final isBusy = _pendingInscription[event.id] == true;

    if (isOrganisateur) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          DropdownButton<String>(
            value: event.statut,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'brouillon', child: Text('Brouillon')),
              DropdownMenuItem(value: 'ouvert', child: Text('Ouvert')),
              DropdownMenuItem(value: 'fermé', child: Text('Fermé')),
              DropdownMenuItem(value: 'archivé', child: Text('Archivé')),
            ],
            onChanged: (value) async {
              if (value == null) return;

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
                streamingUrl: event.streamingUrl,
                flyerUrl: event.flyerUrl,
                views: event.views,
                archivedAt:
                    value == 'archivé' ? DateTime.now() : event.archivedAt,
                lastUpdated: DateTime.now(),
              );

              await eventController.updateEvent(updated, organiser);
            },
          ),
          TextButton(
            onPressed: () => Get.to(() => EventDetailsScreen(event: event)),
            child: const Text('Détails'),
          ),
          TextButton(
            onPressed: () => _confirmDeleteEvent(context, event),
            child: const Text(
              'Supprimer',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ElevatedButton.icon(
          onPressed: (!isParticipant && !isClosed && !isBusy)
              ? () async {
                  setState(() => _pendingInscription[event.id] = true);
                  await eventController.registerToEvent(event.id, currentUser);
                  setState(() => _pendingInscription[event.id] = false);
                }
              : null,
          icon: const Icon(Icons.event_available),
          label: const Text('S’inscrire'),
        ),
        if (isParticipant && !isClosed)
          OutlinedButton(
            onPressed: isBusy
                ? null
                : () => _confirmUnregisterEvent(context, event, currentUser),
            child: const Text(
              'Se désinscrire',
              style: TextStyle(color: Colors.red),
            ),
          )
        else
          OutlinedButton(
            onPressed: () => Get.to(() => EventDetailsScreen(event: event)),
            child: const Text('Détails'),
          ),
      ],
    );
  }

  FloatingActionButton? _buildFloatingActionButton(AppUser currentUser) {
    if (currentUser.role == 'club' || currentUser.role == 'recruteur') {
      return FloatingActionButton(
        onPressed: () => Get.to(() => const EventFormScreen()),
        backgroundColor: AdColors.brand,
        foregroundColor: AdColors.brandOn,
        child: const Icon(Icons.add),
      );
    }
    return null;
  }

  void _confirmDeleteEvent(BuildContext context, Event event) {
    Get.dialog(
      AlertDialog(
        title: const Text('Supprimer'),
        content: const Text('Voulez-vous vraiment supprimer cet événement ?'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await eventController.deleteEvent(event.id, userController.user!);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmUnregisterEvent(
      BuildContext context, Event event, AppUser currentUser) {
    Get.dialog(
      AlertDialog(
        title: const Text('Se désinscrire'),
        content: const Text(
            'Voulez-vous vraiment vous désinscrire de cet événement ?'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await eventController.unregisterFromEvent(event.id, currentUser);
            },
            child: const Text('Confirmer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// 🎨 WIDGETS UTILITAIRES
// =========================================================

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color bg;
    Color fg;

    switch (status) {
      case 'ouvert':
        bg = cs.primary.withValues(alpha: 0.15);
        fg = cs.primary;
        break;
      case 'fermé':
        bg = AdColors.error.withValues(alpha: 0.15);
        fg = AdColors.error;
        break;
      case 'archivé':
        bg = AdColors.onSurfaceMuted.withValues(alpha: 0.15);
        fg = AdColors.onSurfaceMuted;
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
        status,
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
