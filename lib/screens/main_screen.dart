import 'package:flutter/material.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/screens/event_list_screen.dart';
import 'package:show_talent/screens/setting_screen.dart';
import 'package:show_talent/screens/home_screen.dart';
import 'package:show_talent/screens/gestion_offres_screen.dart';
import 'package:show_talent/screens/conversation_screen.dart'; // Ajout de l'écran des conversations
import 'package:get/get.dart';
import 'package:show_talent/controller/chat_controller.dart'; // Ajout du ChatController
import 'package:show_talent/screens/event_form_screen.dart'; // Ajout de l'écran de création/modification d'événements

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final ChatController chatController = Get.put(ChatController()); // Instance du ChatController

  final List<Widget> _screens = [
    const HomeScreen(),
    const GestionOffresScreen(),
    EventListScreen(),  // Liste des événements
    ConversationsScreen(),  // L'écran des conversations
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      floatingActionButton: _selectedIndex == 2 ? FloatingActionButton(
        onPressed: () {
          // Ouvrir l'écran de création d'événement uniquement pour les clubs/recruteurs
          AppUser currentUser = Get.find<UserController>().user!;
          if (currentUser.role == 'recruteur' || currentUser.role == 'club') {
            Get.to(() => EventFormScreen()); // Rediriger vers l'écran de création
          } else {
            Get.snackbar('Accès refusé', 'Seuls les recruteurs et les clubs peuvent créer des événements.');
          }
        },
        child: const Icon(Icons.add),
      ) : null, // Ajouter l'action pour créer un événement uniquement sur l'onglet des événements
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF214D4F),
        selectedItemColor: const Color(0xFFE6EEFA),
        unselectedItemColor: const Color(0xFF8AB98A),
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_offer),
            label: 'Offres',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event),
            label: 'Événements',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),  // Icône de Messages
            label: 'Messages',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
