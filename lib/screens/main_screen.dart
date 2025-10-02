import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/video_controller.dart';

import 'package:adfoot/screens/event_list_screen.dart';
import 'package:adfoot/screens/setting_screen.dart';
import 'package:adfoot/screens/home_screen.dart';
import 'package:adfoot/screens/conversation_screen.dart';
import 'package:adfoot/screens/offre_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';

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
  final VideoController? videoController =
      Get.isRegistered<VideoController>() ? Get.find<VideoController>() : null;

  // Écrans des onglets
  final List<Widget> _screens = [
    const HomeScreen(),
    OffreScreen(),
    EventListScreen(),
    const ConversationsScreen(),
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

  /// ✅ Quand l’utilisateur change d’onglet
  void _onItemTapped(int index) {
    // Si l’utilisateur clique sur Chat, on marque tout comme lu côté local immédiatement
    if (index == 3) {
      chatController.markAllAsReadLocal();
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    // Sécurité : transition après signOut
    if (firebaseUser == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Sécurité : si email non vérifié
    if (firebaseUser.emailVerified != true) {
      if (Get.currentRoute != '/verify') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Get.offAll(() => const VerifyEmailScreen());
        });
      }
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Obx : réagit au profil AppUser + unread Chat
    return Obx(() {
      final appUser = userController.user;

      // 📨 total non-lu (mis à jour par ChatController)
      final unread = chatController.totalUnread;

      return Scaffold(
        body: Column(
          children: [
            if (appUser == null) const _ProfileLoadingBanner(),
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
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Accueil',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.local_offer),
              label: 'Offres',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.event),
              label: 'Events',
            ),
            BottomNavigationBarItem(
              icon: Stack(
                children: [
                  const Icon(Icons.chat),
                  if (unread > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        constraints: const BoxConstraints(
                            minWidth: 16, minHeight: 16),
                        child: Text(
                          unread > 9 ? '9+' : unread.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              label: 'Chat',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Outils',
            ),
          ],
        ),
      );
    });
  }
}

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
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white),
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
