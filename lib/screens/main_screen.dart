import 'dart:ui'; // pour ImageFilter.blur
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/connectivity_controller.dart';

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

  /// 🛰︎ État de la connectivité
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;

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
  void initState() {
    super.initState();
    _listenConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// 👇 Écoute la connectivité réseau et met à jour l’état
  void _listenConnectivity() {
    _connectivitySub =
        ConnectivityService().connectionStream.listen((connected) {
      if (!mounted) return;
      setState(() => _isOnline = connected);
    }, onError: (_) {
      // Si erreur, on conserve l’état précédent
    });

    // Initialisation immédiate
    ConnectivityService().checkInitialConnection().then((connected) {
      if (!mounted) return;
      setState(() => _isOnline = connected);
    }).catchError((_) {});
  }

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
    HapticFeedback.selectionClick();

    // Si l’utilisateur clique sur Chat, on marque tout comme lu côté local
    if (index == 3) {
      chatController.markAllAsReadLocal();
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  /// 👇 Badge + icône Home avec indicateur offline
  Widget _buildHomeIcon({required bool active}) {
    final icon = active ? Icons.home_rounded : Icons.home_outlined;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (!_isOnline)
          const Positioned(
            right: -2,
            top: -2,
            child: CircleAvatar(
              radius: 4,
              backgroundColor: Colors.redAccent,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    // Sécurité: redirection si non connecté
    if (firebaseUser == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Sécurité: email non vérifié
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

    // UI principale
    return Obx(() {
      final appUser = userController.user;
      final unread = chatController.totalUnread;

      return Scaffold(
        body: Column(
          children: [
            if (appUser == null) const _ProfileLoadingBanner(),
            Expanded(child: _screens[_selectedIndex]),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            color: const Color(0xFF214D4F),
            child: ClipRRect(
              clipBehavior: Clip.hardEdge,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [
                        Color(0xFF214D4F),
                        Color(0xFF214D4F),
                      ].map((c) => c.withOpacity(0.95)).toList(),
                    ),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withOpacity(0.06),
                        width: 1,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 14,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: BottomNavigationBar(
                    backgroundColor: Colors.transparent,
                    selectedItemColor: const Color(0xFFE6EEFA),
                    unselectedItemColor: const Color(0xFF8AB98A),
                    currentIndex: _selectedIndex,
                    onTap: _onItemTapped,
                    type: BottomNavigationBarType.fixed,
                    showUnselectedLabels: true,
                    selectedFontSize: 12,
                    unselectedFontSize: 11,
                    selectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                    selectedIconTheme: const IconThemeData(size: 26),
                    unselectedIconTheme: const IconThemeData(size: 24),
                    items: [
                      BottomNavigationBarItem(
                        icon: _buildHomeIcon(active: false),
                        activeIcon: _buildHomeIcon(active: true),
                        label: 'Accueil',
                      ),
                      const BottomNavigationBarItem(
                        icon: Icon(Icons.local_offer_outlined),
                        activeIcon: Icon(Icons.local_offer),
                        label: 'Offres',
                      ),
                      const BottomNavigationBarItem(
                        icon: Icon(Icons.event_outlined),
                        activeIcon: Icon(Icons.event),
                        label: 'Events',
                      ),
                      BottomNavigationBarItem(
                        icon: _ChatIconWithBadge(
                          unread: unread,
                          active: false,
                        ),
                        activeIcon: _ChatIconWithBadge(
                          unread: unread,
                          active: true,
                        ),
                        label: 'Chat',
                      ),
                      const BottomNavigationBarItem(
                        icon: Icon(Icons.settings_outlined),
                        activeIcon: Icon(Icons.settings),
                        label: 'Outils',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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

class _ChatIconWithBadge extends StatelessWidget {
  final int unread;
  final bool active;

  const _ChatIconWithBadge({
    required this.unread,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final baseIcon = active ? Icons.chat_bubble : Icons.chat_bubble_outline;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(baseIcon),
        if (unread > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                unread > 9 ? '9+' : unread.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
