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

class EventDetailsScreen extends StatelessWidget {
  final Event event;

  const EventDetailsScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final AppUser currentUser = Get.find<UserController>().user!;
    final bool isOrganisateur = event.organisateur.uid == currentUser.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Détails de l’événement',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF214D4F),
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
            _buildHeader(),
            const SizedBox(height: 20),
            _buildEventDetails(),
            const SizedBox(height: 24),
            _buildParticipantsSection(context, isOrganisateur),
            // ✅ SECTION FOOTER SUPPRIMÉE (Partager / Calendrier)
          ],
        ),
      ),
    );
  }

  // =========================================================
  // 🧑 HEADER ORGANISATEUR
  // =========================================================

  Widget _buildHeader() {
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
            backgroundColor: Colors.grey.shade200,
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
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                event.organisateur.role,
                style: const TextStyle(color: Colors.grey),
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

  Widget _buildEventDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.titre,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        _buildDetailRow(
          icon: Icons.calendar_today,
          label: 'Dates',
          value:
              'Du ${DateFormat('dd MMM yyyy').format(event.dateDebut)} au ${DateFormat('dd MMM yyyy').format(event.dateFin)}',
        ),

        const SizedBox(height: 12),
        _buildDetailRow(
          icon: Icons.place_outlined,
          label: 'Lieu',
          value: event.lieu,
        ),

        const SizedBox(height: 12),
        _buildDetailRow(
          icon: Icons.privacy_tip_outlined,
          label: 'Visibilité',
          value: event.estPublic ? 'Public' : 'Privé',
        ),

        if (event.capaciteMax != null) ...[
          const SizedBox(height: 12),
          _buildDetailRow(
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
                    label: Text(tag),
                    backgroundColor: Colors.grey.shade200,
                  ),
                )
                .toList(),
          ),
        ],

        const SizedBox(height: 20),
        const Text(
          'Description',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          event.description,
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
      ],
    );
  }

  // =========================================================
  // 👥 PARTICIPANTS
  // =========================================================

  Widget _buildParticipantsSection(BuildContext context, bool isOrganisateur) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Participants',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        if (event.participants.isEmpty)
          const Text(
            'Aucun participant pour le moment.',
            style: TextStyle(color: Colors.grey),
          )
        else
          Column(
            children: event.participants.take(3).map((p) {
              final hasPhoto = p.photoProfil.trim().startsWith('http');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage:
                      hasPhoto ? NetworkImage(p.photoProfil) : null,
                  child: hasPhoto
                      ? null
                      : const Icon(Icons.person, color: Colors.white70),
                ),
                title: Text(p.nom),
                subtitle: Text(p.role),
                onTap: () => Get.to(
                  () => ProfileScreen(uid: p.uid, isReadOnly: true),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  onPressed: () => _openChatWith(p),
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
      backgroundColor: Colors.white,
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
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 16)),
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
    Color color;
    switch (status) {
      case 'ouvert':
        color = Colors.green.shade100;
        break;
      case 'fermé':
        color = Colors.red.shade100;
        break;
      case 'archivé':
        color = Colors.grey.shade300;
        break;
      case 'brouillon':
        color = Colors.orange.shade100;
        break;
      default:
        color = Colors.blueGrey.shade100;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: const TextStyle(fontWeight: FontWeight.bold),
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
    final sorted = [...widget.participants];
    if (sort == 'role') {
      sorted.sort((a, b) => a.role.compareTo(b.role));
    } else {
      sorted.sort((a, b) => a.nom.compareTo(b.nom));
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Participants',
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: sort,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'nom', child: Text('Par nom')),
                    DropdownMenuItem(value: 'role', child: Text('Par rôle')),
                  ],
                  onChanged: (v) => setState(() => sort = v ?? 'nom'),
                ),
              ],
            ),
            const Divider(),
            ...sorted.map((p) {
              final hasPhoto = p.photoProfil.trim().startsWith('http');
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage:
                      hasPhoto ? NetworkImage(p.photoProfil) : null,
                  child: hasPhoto
                      ? null
                      : const Icon(Icons.person, color: Colors.white70),
                ),
                title: Text(p.nom),
                subtitle: Text(p.role),
                onTap: () => Get.to(
                  () => ProfileScreen(uid: p.uid, isReadOnly: true),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
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
    );
  }
}
