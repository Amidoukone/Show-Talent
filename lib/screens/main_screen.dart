import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/controller/chat_controller.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/screens/event_form_screen.dart';
import 'package:show_talent/screens/event_list_screen.dart';
import 'package:show_talent/screens/setting_screen.dart';
import 'package:show_talent/screens/home_screen.dart';
import 'package:show_talent/screens/conversation_screen.dart';
import 'package:show_talent/screens/offre_screen.dart';
import 'package:show_talent/screens/offres_form.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final ChatController chatController = Get.put(ChatController());
  final UserController userController = Get.find<UserController>();

  final List<Widget> _screens = [
    const HomeScreen(),
    OffreScreen(), // Ajouter l'écran des offres ici
    EventListScreen(),
    ConversationsScreen(),
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Vérifier si le UserController est prêt
      if (userController.user == null) {
        return Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      }
      return Scaffold(
        body: _screens[_selectedIndex],
        floatingActionButton: _buildFloatingActionButton(),
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
              label: 'Offers',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.event),
              label: 'Events',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat),
              label: 'Messages',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      );
    });
  }

  Widget? _buildFloatingActionButton() {
    AppUser? currentUser = userController.user;

    // Afficher le bouton pour publier un événement ou une offre
    if (_selectedIndex == 2 && currentUser != null) {
      if (currentUser.role == 'recruteur' || currentUser.role == 'club') {
        return FloatingActionButton(
          onPressed: () {
            Get.bottomSheet(
              const EventFormScreen(),
              isScrollControlled: true,
              backgroundColor: Colors.white,
            );
          },
          backgroundColor: const Color(0xFF214D4F),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        );
      }
    }

    if (_selectedIndex == 1 && currentUser != null) {
      if (currentUser.role == 'recruteur' || currentUser.role == 'club') {
        return FloatingActionButton(
          onPressed: () {
            Get.to(() => OffreFormScreen());
          },
          backgroundColor: const Color(0xFF214D4F),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        );
      }
    }

    return null;
  }
}
