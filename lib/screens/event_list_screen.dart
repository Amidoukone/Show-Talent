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

  EventListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    AppUser currentUser = Get.find<UserController>().user!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liste des événements'),
        backgroundColor: const Color(0xFF214D4F),
        centerTitle: true,
      ),
      body: Obx(() {
        if (eventController.events.isEmpty) {
          return const Center(
              child: Text('Aucun événement disponible pour l\'instant.'));
        } else {
          return ListView.builder(
            itemCount: eventController.events.length,
            itemBuilder: (context, index) {
              Event event = eventController.events[index];
              AppUser organiser = event.organisateur;
              bool isParticipant =
                  event.participants.any((p) => p.uid == currentUser.uid);

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15.0)),
                  elevation: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section organisateur
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                // Redirige vers le profil en lecture seule
                                Get.to(() => ProfileScreen(
                                      uid: organiser.uid,
                                      isReadOnly: true,
                                    ));
                              },
                              child: CircleAvatar(
                                radius: 25,
                                backgroundImage: NetworkImage(
                                  organiser.photoProfil.isNotEmpty
                                      ? organiser.photoProfil
                                      : 'https://via.placeholder.com/150',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  organiser.nom.isNotEmpty
                                      ? organiser.nom
                                      : 'Utilisateur inconnu',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  organiser.role == 'club'
                                      ? 'Club'
                                      : 'Recruteur',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Détails de l'événement
                        Text(
                          event.titre,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Lieu: ${event.lieu}',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Statut: ${event.statut}',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        const SizedBox(height: 20),

                        // Boutons d'action
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton.icon(
                              onPressed:
                                  (isParticipant || event.statut == 'Terminé')
                                      ? null
                                      : () {
                                          // Inscription à l'événement
                                          eventController.registerToEvent(
                                              event.id, currentUser);
                                        },
                              icon: const Icon(Icons.check_circle,
                                  color: Colors.white),
                              label: const Text(
                                'S\'inscrire',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    (isParticipant || event.statut == 'Terminé')
                                        ? Colors.grey
                                        : const Color(0xFF66BB6A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                // Voir les détails de l'événement
                                Get.to(() => EventDetailsScreen(event: event));
                              },
                              icon: const Icon(Icons.info_outline,
                                  color: Color(0xFF2E7D32)),
                              label: const Text(
                                'Voir les détails',
                                style: TextStyle(color: Color(0xFF2E7D32)),
                              ),
                              style: OutlinedButton.styleFrom(
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
                ),
              );
            },
          );
        }
      }),
    );
  }
}
