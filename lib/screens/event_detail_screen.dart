import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/user_controller.dart';

import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';

import 'package:adfoot/screens/event_form_screen.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/screens/chat_screen.dart';
import 'package:adfoot/theme/ad_colors.dart';

class EventDetailsScreen extends StatelessWidget {
  final Event event;

  const EventDetailsScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final AppUser currentUser = Get.find<UserController>().user!;
    final bool isOrganisateur = event.organisateur.uid == currentUser.uid;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text(
          'Détails de l’événement',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        centerTitle: true,
        actions: isOrganisateur
            ? [
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Modifier',
                  onPressed: () async {
                    final updated =
                        await Get.to(() => EventFormScreen(event: event));
                    if (updated == true) {
                      Get.find<EventController>().fetchEvents();
                      Get.offAllNamed('/main', arguments: 2);
                    }
                  },
                ),
              ]
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 18),
            _buildEventDetails(context),
            const SizedBox(height: 22),
            _buildParticipantsSection(context, isOrganisateur),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // 🧑 HEADER ORGANISATEUR
  // =========================================================

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPhoto = event.organisateur.photoProfil.trim().startsWith('http');

    return Row(
      children: [
        GestureDetector(
          onTap: () => Get.to(
            () => ProfileScreen(
              uid: event.organisateur.uid,
              isReadOnly: true,
            ),
          ),
          child: CircleAvatar(
            radius: 26,
            backgroundColor: AdColors.surfaceCardAlt,
            backgroundImage:
                hasPhoto ? NetworkImage(event.organisateur.photoProfil) : null,
            child:
                hasPhoto ? null : const Icon(Icons.person, color: Colors.white70),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.organisateur.nom.isNotEmpty
                    ? event.organisateur.nom
                    : 'Organisateur',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                event.organisateur.role,
                style: const TextStyle(
                  color: AdColors.onSurfaceMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        _StatusBadge(status: event.statut),
      ],
    );
  }

  // =========================================================
  // 📄 DÉTAILS ÉVÉNEMENT
  // =========================================================

  Widget _buildEventDetails(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.titre,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 14),

        _buildDetailRow(
          context: context,
          icon: Icons.calendar_today,
          label: 'Dates',
          value:
              'Du ${DateFormat('dd MMM yyyy').format(event.dateDebut)} au ${DateFormat('dd MMM yyyy').format(event.dateFin)}',
        ),

        const SizedBox(height: 12),
        _buildDetailRow(
          context: context,
          icon: Icons.place_outlined,
          label: 'Lieu',
          value: event.lieu,
        ),

        const SizedBox(height: 12),
        _buildDetailRow(
          context: context,
          icon: Icons.privacy_tip_outlined,
          label: 'Visibilité',
          value: event.estPublic ? 'Public' : 'Privé',
        ),

        if (event.capaciteMax != null) ...[
          const SizedBox(height: 12),
          _buildDetailRow(
            context: context,
            icon: Icons.groups,
            label: 'Capacité',
            value:
                '${event.participants.length} / ${event.capaciteMax} participants',
          ),
        ],

        if (event.tags != null && event.tags!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: event.tags!
                .map(
                  (tag) => Chip(
                    label: Text(
                      tag,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: AdColors.surfaceCard,
                    side: const BorderSide(color: AdColors.divider),
                  ),
                )
                .toList(),
          ),
        ],

        const SizedBox(height: 20),
        Text(
          'Description',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          event.description,
          style: TextStyle(
            fontSize: 15.5,
            height: 1.55,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // 👥 PARTICIPANTS
  // =========================================================

  Widget _buildParticipantsSection(BuildContext context, bool isOrganisateur) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Participants',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),

        if (event.participants.isEmpty)
          const Text(
            'Aucun participant pour le moment.',
            style: TextStyle(color: AdColors.onSurfaceMuted),
          )
        else
          Column(
            children: event.participants.take(3).map((p) {
              final hasPhoto = p.photoProfil.trim().startsWith('http');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AdColors.surfaceCardAlt,
                  backgroundImage:
                      hasPhoto ? NetworkImage(p.photoProfil) : null,
                  child: hasPhoto
                      ? null
                      : const Icon(Icons.person, color: Colors.white70),
                ),
                title: Text(
                  p.nom,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: const Text(
                  '',
                  style: TextStyle(height: 0),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.chat_bubble_outline, color: cs.primary),
                  onPressed: () => _openChatWith(p),
                ),
                onTap: () => Get.to(
                  () => ProfileScreen(uid: p.uid, isReadOnly: true),
                ),
              );
            }).toList(),
          ),

        if (event.participants.length > 3)
          TextButton(
            onPressed: () => _showParticipants(event.participants),
            child: const Text('Voir tous les participants'),
          )
        else if (isOrganisateur && event.participants.isEmpty)
          TextButton(
            onPressed: () => _showParticipants(event.participants),
            child: const Text('Gérer les participants'),
          ),
      ],
    );
  }

  // =========================================================
  // 🔽 MODAL PARTICIPANTS (TRI + CHAT)
  // =========================================================

  void _showParticipants(List<AppUser> participants) {
    showModalBottomSheet(
      context: Get.context!,
      backgroundColor: AdColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ParticipantsModal(participants: participants),
    );
  }

  // =========================================================
  // 🧩 HELPERS
  // =========================================================

  Widget _buildDetailRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AdColors.onSurfaceMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15.5,
                  color: AdColors.onSurfaceMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openChatWith(AppUser other) async {
    final chat = Get.isRegistered<ChatController>()
        ? Get.find<ChatController>()
        : Get.put(ChatController());

    final current = Get.find<UserController>().user;
    if (current == null) return;

    final convId = await chat.createOrGetConversation(
      currentUserId: current.uid,
      otherUserId: other.uid,
    );

    Get.to(() => ChatScreen(
          conversationId: convId,
          otherUser: other,
        ));
  }
}
// =========================================================
// 🎨 BADGE STATUT
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
        border: Border.all(color: AdColors.divider),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

// =========================================================
// 👥 MODAL PARTICIPANTS AVEC TRI
// =========================================================

class _ParticipantsModal extends StatefulWidget {
  final List<AppUser> participants;

  const _ParticipantsModal({required this.participants});

  @override
  State<_ParticipantsModal> createState() => _ParticipantsModalState();
}

class _ParticipantsModalState extends State<_ParticipantsModal> {
  String sort = 'nom';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final sorted = [...widget.participants];
    if (sort == 'role') {
      sorted.sort((a, b) => a.role.compareTo(b.role));
    } else {
      sorted.sort((a, b) => a.nom.compareTo(b.nom));
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Participants',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                  DropdownButton<String>(
                    value: sort,
                    underline: const SizedBox.shrink(),
                    dropdownColor: AdColors.surfaceCard,
                    items: const [
                      DropdownMenuItem(value: 'nom', child: Text('Par nom')),
                      DropdownMenuItem(value: 'role', child: Text('Par rôle')),
                    ],
                    onChanged: (v) => setState(() => sort = v ?? 'nom'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(color: AdColors.divider),

              ...sorted.map((p) {
                final hasPhoto = p.photoProfil.trim().startsWith('http');

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AdColors.surfaceCardAlt,
                    backgroundImage: hasPhoto ? NetworkImage(p.photoProfil) : null,
                    child: hasPhoto
                        ? null
                        : const Icon(Icons.person, color: Colors.white70),
                  ),
                  title: Text(
                    p.nom,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    p.role,
                    style: const TextStyle(color: AdColors.onSurfaceMuted),
                  ),
                  onTap: () => Get.to(
                    () => ProfileScreen(uid: p.uid, isReadOnly: true),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.chat_bubble_outline, color: cs.primary),
                    onPressed: () async {
                      final chat = Get.isRegistered<ChatController>()
                          ? Get.find<ChatController>()
                          : Get.put(ChatController());

                      final current = Get.find<UserController>().user;
                      if (current == null) return;

                      final convId = await chat.createOrGetConversation(
                        currentUserId: current.uid,
                        otherUserId: p.uid,
                      );

                      Get.to(() => ChatScreen(
                            conversationId: convId,
                            otherUser: p,
                          ));
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
