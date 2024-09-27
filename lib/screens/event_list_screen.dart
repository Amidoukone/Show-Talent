
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/event_controller.dart';
import 'package:show_talent/models/event.dart';



class EventListScreen extends StatelessWidget {
  final EventController eventController = Get.put(EventController());

  EventListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Événements')),
      body: Obx(() {
        if (eventController.events.isEmpty) {
          return const Center(child: Text('Aucun événement disponible pour l\'instant.'));
        } else {
          return ListView.builder(
            itemCount: eventController.events.length,
            itemBuilder: (context, index) {
              Event event = eventController.events[index];
              return ListTile(
                title: Text(event.titre),
                subtitle: Text(event.description),
                trailing: Text(event.statut),
                onTap: () {
                  // Afficher les détails de l'événement ou permettre l'inscription
                },
              );
            },
          );
        }
      }),
    );
  }
}
