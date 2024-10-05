import 'package:flutter/material.dart';
import 'offre_screen.dart'; 
import 'publier_offre_screen.dart';

class GestionOffresScreen extends StatelessWidget {
  const GestionOffresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestion des Offres'),
          backgroundColor: const Color(0xFF214D4F),  // Couleur principale
          bottom: const TabBar(
            indicatorColor: Colors.white,  // Couleur de l'indicateur d'onglet
            tabs: [
              Tab(text: 'Afficher Offres'),
              Tab(text: 'Publier Offre'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            OffresScreen(),  
            PublierOffreScreen(),  
          ],
        ),
      ),
    );
  }
}
