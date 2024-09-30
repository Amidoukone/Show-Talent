import 'package:flutter/material.dart';
import '../models/offre.dart';

class OffreDetailsScreen extends StatelessWidget {
  final Offre offre;

  const OffreDetailsScreen({super.key, required this.offre});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(offre.titre)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Titre: ${offre.titre}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Description: ${offre.description}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text('Statut: ${offre.statut}'),
            const SizedBox(height: 10),
            Text('Date de début: ${offre.dateDebut.toLocal()}'),
            Text('Date de fin: ${offre.dateFin.toLocal()}'),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                // Logique pour postuler à cette offre
                // Appel de l'OffreController pour postuler
                // OffreController.instance.postulerOffre(offre);
              },
              child: const Text('Postuler'),
            ),
          ],
        ),
      ),
    );
  }
}
