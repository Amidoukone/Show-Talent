import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/event_form_screen.dart';
import 'package:adfoot/screens/profile_screen.dart';

class EventDetailsScreen extends StatelessWidget {
  final Event event;

  const EventDetailsScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    AppUser currentUser = Get.find<UserController>().user!;
    bool isOrganisateur = event.organisateur.uid == currentUser.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Détails de l\'événement',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF214D4F),
        centerTitle: true,
        actions: isOrganisateur
            ? [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  tooltip: 'Modifier',
                  onPressed: () async {
                    final updated = await Get.to(() => EventFormScreen(event: event));
                    if (updated == true) {
                      Get.find<EventController>().fetchEvents();
                      Get.offAllNamed('/main', arguments: 2); // ✅ Revenir à EventListScreen avec bottom bar
                    }
                  },
                ),
              ]
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEventDetails(),
            const SizedBox(height: 20),
            if (isOrganisateur) _buildOrganisateurActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildEventDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.titre,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildDetailRow(
          icon: Icons.calendar_today,
          label: 'Dates',
          value: 'Du ${_formatDate(event.dateDebut)} au ${_formatDate(event.dateFin)}',
        ),
        const SizedBox(height: 16),
        _buildDetailRow(
          icon: Icons.location_on,
          label: 'Lieu',
          value: event.lieu,
        ),
        const SizedBox(height: 16),
        const Text(
          'Description',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          event.description,
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Text(
              'Statut: ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              event.statut,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _getStatusColor(event.statut),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOrganisateurActions() {
    return ElevatedButton.icon(
      onPressed: () {
        _showParticipants(event.participants);
      },
      icon: const Icon(Icons.people),
      label: const Text('Voir les participants'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF214D4F),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  void _showParticipants(List<AppUser> participants) {
    showModalBottomSheet(
      context: Get.context!,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Participants', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Divider(),
              if (participants.isEmpty)
                const Center(
                  child: Text('Aucun participant pour le moment.', style: TextStyle(fontSize: 16, color: Colors.grey)),
                )
              else
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: participants.length,
                  itemBuilder: (context, index) {
                    AppUser participant = participants[index];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 25,
                        backgroundImage: NetworkImage(participant.photoProfil),
                        backgroundColor: Colors.grey.shade300,
                      ),
                      title: Text(participant.nom),
                      subtitle: Text(participant.email),
                      onTap: () {
                        Get.to(() => ProfileScreen(uid: participant.uid, isReadOnly: true));
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

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
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String statut) {
    switch (statut) {
      case 'Terminé':
        return Colors.red;
      case 'En cours':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
