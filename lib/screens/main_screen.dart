import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ Ajout : on se base sur l'état auth Firebase

import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/video_controller.dart';

import 'package:adfoot/screens/event_list_screen.dart';
import 'package:adfoot/screens/setting_screen.dart';
import 'package:adfoot/screens/home_screen.dart';
import 'package:adfoot/screens/conversation_screen.dart';
import 'package:adfoot/screens/offre_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Controllers
  final UserController userController = Get.find<UserController>();
  final ChatController chatController = Get.put(ChatController());
  final VideoController? videoController = Get.isRegistered<VideoController>()
      ? Get.find<VideoController>()
      : null;

  // Onglets
  final List<Widget> _screens = [
    HomeScreen(),
    OffreScreen(),
    EventListScreen(),
    ConversationsScreen(),
    SettingsScreen(),
  ];

  bool _hasHandledArguments = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasHandledArguments) {
      final args = Get.arguments;

      if (args != null) {
        if (args is int) {
          _selectedIndex = args;
        } else if (args is Map) {
          _selectedIndex = args['tab'] ?? 0;
          if (args['refresh'] == true) {
            videoController?.refreshVideos();
          }
        }
      }
      _hasHandledArguments = true;
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ IMPORTANT : on ne bloque plus l'UI sur userController.user.
    // On s'appuie d'abord sur Firebase pour savoir si un user est authentifié.
    final firebaseUser = FirebaseAuth.instance.currentUser;

    // Cas rare (transition/refresh/juste après signOut) :
    // on laisse AuthController rerouter proprement vers Login si besoin.
    if (firebaseUser == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // On garde Obx pour réagir aux mises à jour (ex: AppUser hydraté, listes users, etc.).
    return Obx(() {
      // 🟢 À ce niveau, l'utilisateur est authentifié (firebaseUser != null).
      // userController.user peut encore être null (doc Firestore pas encore hydraté) :
      // on n'en fait PAS une condition bloquante pour toute l'app.
      final appUser = userController.user;

      return Scaffold(
        // Astuce UX : petit bandeau d'info (non bloquant) tant que le profil AppUser se charge.
        // Tu peux l'enlever si tu veux zéro UI additionnelle.
        body: Column(
          children: [
            if (appUser == null)
              const _ProfileLoadingBanner(), // bandeau fin, optionnel
            // Le contenu principal de l'onglet sélectionné
            Expanded(child: _screens[_selectedIndex]),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: const Color(0xFF214D4F),
          selectedItemColor: const Color(0xFFE6EEFA),
          unselectedItemColor: const Color(0xFF8AB98A),
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
            BottomNavigationBarItem(icon: Icon(Icons.local_offer), label: 'Offres'),
            BottomNavigationBarItem(icon: Icon(Icons.event), label: 'Events'),
            BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Outils'),
          ],
        ),
      );
    });
  }
}

/// Petit bandeau d'information quand le profil AppUser n'est pas encore hydraté.
/// Non bloquant, discret. Tu peux le retirer si tu préfères.
class _ProfileLoadingBanner extends StatelessWidget {
  const _ProfileLoadingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      width: double.infinity,
      color: const Color(0xFF214D4F),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          SizedBox(width: 8),
          Text(
            'Chargement du profil…',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
