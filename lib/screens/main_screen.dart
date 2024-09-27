
import 'package:flutter/material.dart';
import 'package:show_talent/screens/event_list_screen.dart';
import 'package:show_talent/screens/setting_screen.dart';

// Importation des différents screens corrects
import 'home_screen.dart';
import 'publier_offre_screen.dart';
import 'search_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // Indice de l'onglet sélectionné

  // Liste des pages (écrans) correspondant aux onglets de la navigation
  final List<Widget> _screens = [
    const HomeScreen(),
    PublierOffreScreen(), // Utilisation des bons fichiers ici
    EventListScreen(),
    SearchScreen(),
    SettingsScreen(),
  ];

  // Méthode pour changer l'index en fonction de l'onglet cliqué
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex], // Affichage de la page actuelle
      bottomNavigationBar: Container(
        color: const Color(0xFF004d00), // Vert foncé appliqué via le Container
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent, // Important: on laisse transparent ici
          selectedItemColor: Colors.white, // Couleur des icônes sélectionnées
          unselectedItemColor: const Color(0xFF8AB98A), // Couleur des icônes non sélectionnées
          currentIndex: _selectedIndex, // Index de la page actuelle
          onTap: _onItemTapped, // Gérer le changement d'onglet
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.local_offer),
              label: 'Publier Offre',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.event),
              label: 'Événements',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: 'Search',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
