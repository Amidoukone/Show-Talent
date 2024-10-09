import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/event_controller.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/models/event.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/screens/profile_screen.dart'; // Pour afficher le profil des participants
import 'event_form_screen.dart'; // Pour modifier l'événement

class EventDetailsScreen extends StatelessWidget {
  final Event event;

  const EventDetailsScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    AppUser currentUser = Get.find<UserController>().user!;
    bool isOrganisateur = event.organisateur.uid == currentUser.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détails de l\'événement'),
        backgroundColor: const Color(0xFF214D4F),
        actions: isOrganisateur
            ? [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Get.to(() => EventFormScreen(event: event));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    Get.defaultDialog(
                      title: 'Confirmation',
                      content: const Text('Êtes-vous sûr de vouloir supprimer cet événement ?'),
                      onConfirm: () {
                        Get.find<EventController>().deleteEvent(event.id);
                        Get.back(); // Retour à la liste des événements après suppression
                      },
                      onCancel: () {},
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
            Text(
              event.titre,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Wrap( // Utilisation de Wrap pour permettre à la date de passer à la ligne si nécessaire
              children: [
                const Icon(Icons.calendar_today, color: Colors.grey),
                const SizedBox(width: 10),
                Text(
                  'Du ${event.dateDebut.toLocal()} au ${event.dateFin.toLocal()}',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap( // Utilisation de Wrap ici également
              children: [
                const Icon(Icons.location_on, color: Colors.grey),
                const SizedBox(width: 10),
                Text(
                  event.lieu,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Description',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              event.description,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('Statut: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  event.statut,
                  style: const TextStyle(fontSize: 16, color: Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Si c'est l'organisateur, ajouter un bouton pour voir les inscrits et changer le statut
            if (isOrganisateur)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      _showParticipants(context, event.participants);
                    },
                    icon: const Icon(Icons.people),
                    label: const Text('Voir les inscrits'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF214D4F), // Fond bleu foncé
                      foregroundColor: Colors.white, // Texte en blanc
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
                    child: const Text('Marquer comme Terminé'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF214D4F), // Fond bleu foncé
                      foregroundColor: Colors.white, // Texte en blanc
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // Afficher la liste des participants inscrits avec leurs informations de profil
  void _showParticipants(BuildContext context, List<AppUser> participants) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Candidats inscrits', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ListView.builder(
                physics: const NeverScrollableScrollPhysics(), // Désactiver le scroll dans la ListView
                shrinkWrap: true,
                itemCount: participants.length,
                itemBuilder: (context, index) {
                  AppUser participant = participants[index];
                  return Card(
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text(participant.nom),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Email: ${participant.email}'),
                          if (participant.role == 'joueur') Text('Position: ${participant.position ?? "Non spécifiée"}'),
                          if (participant.clubActuel != null) Text('Club: ${participant.clubActuel}')
                        ],
                      ),
                      onTap: () {
                        Get.to(() => ProfileScreen(uid: participant.uid, isReadOnly: true));
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Marquer l'événement comme "Terminé" et verrouiller les inscriptions
  void _updateEventStatus(BuildContext context) {
    Get.defaultDialog(
      title: 'Confirmer',
      middleText: 'Voulez-vous marquer cet événement comme Terminé ?',
      textConfirm: 'Oui',
      textCancel: 'Non',
      onConfirm: () {
        event.statut = 'Terminé';
        Get.find<EventController>().updateEvent(event);
        Get.back(); // Fermer le dialog
      },
    );
  }
}
