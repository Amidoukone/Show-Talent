import 'package:flutter/material.dart';
import 'package:show_talent/controller/auth_controller.dart';  // Importer pour vérifier le rôle de l'utilisateur
import 'package:show_talent/models/user.dart';
import 'offre_screen.dart'; 
import 'publier_offre_screen.dart';

class GestionOffresScreen extends StatelessWidget {
  const GestionOffresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    AppUser? currentUser = AuthController.instance.user;  // Obtenir l'utilisateur actuel

    // Vérifier si l'utilisateur est un recruteur ou un club
    bool isClubOrRecruteur = currentUser != null &&
        (currentUser.role == 'recruteur' || currentUser.role == 'club');

    return DefaultTabController(
      length: isClubOrRecruteur ? 2 : 1,  // Afficher 2 onglets pour les clubs/recruteurs et 1 seul pour les autres
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestion des Offres'),
          backgroundColor: const Color(0xFF214D4F),  // Couleur principale
          bottom: TabBar(
            indicatorColor: Colors.white,  // Couleur de l'indicateur d'onglet
            labelColor: Colors.white,  // Couleur du texte sélectionné
            unselectedLabelColor: Colors.white70,  // Couleur du texte non sélectionné
            tabs: [
              const Tab(
                child: Text(
                  'Afficher Offres',
                  style: TextStyle(color: Colors.white),  // Appliquer la couleur blanche
                ),
              ),
              if (isClubOrRecruteur)  // Afficher "Publier Offre" uniquement pour clubs et recruteurs
                const Tab(
                  child: Text(
                    'Publier Offre',
                    style: TextStyle(color: Colors.white),  // Appliquer la couleur blanche
                  ),
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const OffresScreen(),  
            if (isClubOrRecruteur) const PublierOffreScreen(),  // Inclure la page "Publier Offre" seulement pour clubs/recruteurs
          ],
        ),
      ),
    );
  }
}
