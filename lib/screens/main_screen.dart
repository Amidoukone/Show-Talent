import 'package:flutter/material.dart';
import 'package:get/get.dart';
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

  final UserController userController = Get.find<UserController>();
  final ChatController chatController = Get.put(ChatController());
  final VideoController? videoController = Get.isRegistered<VideoController>()
      ? Get.find<VideoController>()
      : null;

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
    return Obx(() {
      if (userController.user == null) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      return Scaffold(
        body: _screens[_selectedIndex],
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
            BottomNavigationBarItem(icon: Icon(Icons.event), label: 'Événements'),
            BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Messages'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Paramètres'),
          ],
        ),
      );
    });
  }
}
