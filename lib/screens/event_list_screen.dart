import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/event_controller.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/models/event.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/screens/event_detail_screen.dart';

class EventListScreen extends StatelessWidget {
  final EventController eventController = Get.put(EventController());

  EventListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    AppUser currentUser = Get.find<UserController>().user!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Événements'),
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: Obx(() {
        if (eventController.events.isEmpty) {
          return const Center(child: Text('Aucun événement disponible pour l\'instant.'));
        } else {
          return ListView.builder(
            itemCount: eventController.events.length,
            itemBuilder: (context, index) {
              Event event = eventController.events[index];
              bool isParticipant = event.participants.any((p) => p.uid == currentUser.uid);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
                  elevation: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                          style: const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Statut: ${event.statut}',
                          style: const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton.icon(
                              onPressed: (isParticipant || event.statut == 'Terminé')
                                  ? null
                                  : () {
                                      // Inscription à l'événement
                                      eventController.registerToEvent(event.id, currentUser);
                                    },
                              icon: const Icon(Icons.check_circle, color: Colors.white), // Icon en blanc
                              label: const Text(
                                'S\'inscrire',
                                style: TextStyle(color: Colors.white), // Texte en blanc
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: (isParticipant || event.statut == 'Terminé')
                                    ? Colors.grey
                                    : const Color(0xFF66BB6A), // Vert clair
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
                              icon: const Icon(Icons.info_outline, color: Color(0xFF2E7D32)), // Icon en vert foncé
                              label: const Text(
                                'Voir les détails',
                                style: TextStyle(color: Color(0xFF2E7D32)), // Texte en vert foncé
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
