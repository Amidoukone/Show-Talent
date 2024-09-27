import 'package:flutter/material.dart';

import '../controller/offre_controller.dart';

class PublierOffreScreen extends StatelessWidget {
  final TextEditingController titreController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final DateTime dateDebut = DateTime.now();
  final DateTime dateFin = DateTime.now().add(const Duration(days: 30));

  PublierOffreScreen({super.key}); // Durée d'un mois

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Publier une Offre'),),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            TextField(
              controller: titreController,
              decoration: const InputDecoration(labelText: 'Titre de l\'offre'),
            ),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                OffreController.instance.publierOffre(
                  titreController.text,
                  descriptionController.text,
                  dateDebut,
                  dateFin,
                );
              },
              child: const Text('Publier'),
            ),
          ],
        ),
      ),
    );
  }
}
