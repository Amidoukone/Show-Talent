import 'package:flutter/material.dart';
import 'offre_screen.dart'; // Écran pour afficher les offres
import 'publier_offre_screen.dart'; // Écran pour publier une offre

class GestionOffresScreen extends StatelessWidget {
  const GestionOffresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // Deux onglets : Afficher Offres et Publier Offre
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestion des Offres'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Afficher Offres'),  // Onglet pour afficher les offres
              Tab(text: 'Publier Offre'),    // Onglet pour publier une offre
            ],
          ),
        ),
        body:  TabBarView(
          children: [
            OffresScreen(),  // Vue pour afficher les offres
            PublierOffreScreen(),  // Vue pour publier une offre
          ],
        ),
      ),
    );
  }
}
