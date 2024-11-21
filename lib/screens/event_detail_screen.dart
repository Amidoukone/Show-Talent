import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/event_controller.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/models/event.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/screens/profile_screen.dart';
import 'event_form_screen.dart';

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
                  onPressed: () {
                    Get.to(() => EventFormScreen(event: event));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.white),
                  tooltip: 'Supprimer',
                  onPressed: () {
                    Get.defaultDialog(
                      title: 'Confirmation',
                      middleText: 'Êtes-vous sûr de vouloir supprimer cet événement ?',
                      textConfirm: 'Oui',
                      textCancel: 'Non',
                      onConfirm: () {
                        Get.find<EventController>().deleteEvent(event.id);
                        Get.back(); // Fermer la boîte de dialogue
                      },
                    );
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
            // Titre de l'événement
            Text(
              event.titre,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 16),
            
            // Dates
            _buildDetailRow(
              icon: Icons.calendar_today,
              label: 'Dates',
              value: 'Du ${_formatDate(event.dateDebut)} au ${_formatDate(event.dateFin)}',
            ),
            const SizedBox(height: 16),

            // Lieu
            _buildDetailRow(
              icon: Icons.location_on,
              label: 'Lieu',
              value: event.lieu,
            ),
            const SizedBox(height: 16),

            // Description
            const Text(
              'Description',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              event.description,
              style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
            ),
            const SizedBox(height: 20),

            // Statut
            Row(
              children: [
                const Text(
                  'Statut: ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  event.statut,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Actions spécifiques pour l'organisateur
            if (isOrganisateur)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      _showParticipants(context, event.participants);
                    },
                    icon: const Icon(Icons.people),
                    label: const Text('Voir les participants'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF214D4F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      _updateEventStatus(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF214D4F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text('Marquer comme Terminé'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({required IconData icon, required String label, required String value}) {
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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Formater la date pour l'affichage
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // Afficher la liste des participants
  void _showParticipants(BuildContext context, List<AppUser> participants) {
    showModalBottomSheet(
      context: context,
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
              const Text(
                'Participants',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              if (participants.isEmpty)
                const Center(
                  child: Text(
                    'Aucun participant pour le moment.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
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

  // Modifier le statut de l'événement
  void _updateEventStatus(BuildContext context) {
    Get.defaultDialog(
      title: 'Confirmer',
      middleText: 'Voulez-vous marquer cet événement comme "Terminé" ?',
      textConfirm: 'Oui',
      textCancel: 'Non',
      onConfirm: () {
        event.statut = 'Terminé';
        Get.find<EventController>().updateEvent(event);
        Get.back(); // Fermer la boîte de dialogue
      },
    );
  }
}
