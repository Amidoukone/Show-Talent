import 'package:adfoot/screens/event_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/event_detail_screen.dart';
import 'package:adfoot/screens/profile_screen.dart';

class EventListScreen extends StatelessWidget {
  final EventController eventController = Get.put(EventController());
  final UserController userController = Get.find<UserController>();

  EventListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppUser currentUser = userController.user!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liste des événements'),
        backgroundColor: const Color(0xFF214D4F),
        centerTitle: true,
      ),
      body: Obx(() {
        if (eventController.events.isEmpty) {
          return const Center(
            child: Text(
              'Aucun événement disponible pour l\'instant.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        } else {
          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: eventController.events.length,
            itemBuilder: (context, index) {
              Event event = eventController.events[index];
              AppUser organiser = event.organisateur;
              bool isParticipant = event.participants.any((p) => p.uid == currentUser.uid);
              bool isOrganisateur = currentUser.uid == organiser.uid;

              return _buildEventCard(context, event, organiser, isParticipant, isOrganisateur, currentUser);
            },
          );
        }
      }),
      floatingActionButton: _buildFloatingActionButton(currentUser),
    );
  }

  Widget _buildEventCard(BuildContext context, Event event, AppUser organiser, bool isParticipant, bool isOrganisateur, AppUser currentUser) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      elevation: 5,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrganiserSection(context, organiser),
            const SizedBox(height: 10),
            _buildEventDetails(event),
            const SizedBox(height: 20),
            isOrganisateur ? _buildOrganisateurActions(context, event) : _buildParticipantActions(context, event, currentUser, isParticipant),
          ],
        ),
      ),
    );
  }

  Widget _buildOrganiserSection(BuildContext context, AppUser organiser) {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            Get.to(() => ProfileScreen(uid: organiser.uid, isReadOnly: true));
          },
          child: CircleAvatar(
            radius: 25,
            backgroundImage: NetworkImage(organiser.photoProfil.isNotEmpty ? organiser.photoProfil : 'https://via.placeholder.com/150'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                organiser.nom.isNotEmpty ? organiser.nom : 'Utilisateur inconnu',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                organiser.role == 'club' ? 'Club' : 'Recruteur',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEventDetails(Event event) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.titre,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Text('Lieu: ${event.lieu}', style: const TextStyle(color: Colors.grey, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 5),
        Text('Statut: ${event.statut}', style: const TextStyle(color: Colors.grey, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildOrganisateurActions(BuildContext context, Event event) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: () {
            _markAsCompleted(context, event);
          },
          child: const Text('Terminer', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: () {
            Get.to(() => EventDetailsScreen(event: event));
          },
          child: const Text('Voir les détails', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: () {
            _confirmDeleteEvent(context, event);
          },
          child: const Text('Supprimer', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildParticipantActions(BuildContext context, Event event, AppUser currentUser, bool isParticipant) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ElevatedButton.icon(
          onPressed: (isParticipant || event.statut == 'Terminé') ? null : () {
            eventController.registerToEvent(event.id, currentUser);
          },
          icon: const Icon(Icons.check_circle, color: Colors.white),
          label: const Text('S\'inscrire', style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: (isParticipant || event.statut == 'Terminé') ? Colors.grey : const Color(0xFF66BB6A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () {
            Get.to(() => EventDetailsScreen(event: event));
          },
          icon: const Icon(Icons.info_outline, color: Color(0xFF2E7D32)),
          label: const Text('Voir les détails', style: TextStyle(color: Color(0xFF2E7D32)))),
      ],
    );
  }

  FloatingActionButton? _buildFloatingActionButton(AppUser currentUser) {
    if (currentUser.role == 'club' || currentUser.role == 'recruteur') {
      return FloatingActionButton(
        onPressed: () {
          Get.to(() => EventFormScreen());
        },
        backgroundColor: const Color(0xFF214D4F),
        foregroundColor: Colors.white,
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
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              await eventController.deleteEvent(event.id, userController.user!);
              Get.back();
              Get.snackbar('Succès', 'Événement supprimé avec succès.', backgroundColor: Colors.green.shade100, colorText: Colors.black87);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _markAsCompleted(BuildContext context, Event event) {
    event.statut = 'Terminé';
    eventController.updateEvent(event, userController.user!);
    Get.snackbar('Succès', 'Événement marqué comme terminé.', backgroundColor: Colors.orange.shade100, colorText: Colors.black87);
  }
}
