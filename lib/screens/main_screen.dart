import 'dart:async';
import 'dart:ui';

import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/connectivity_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/screens/conversation_screen.dart';
import 'package:adfoot/screens/event_list_screen.dart';
import 'package:adfoot/screens/home_screen.dart';
import 'package:adfoot/screens/offre_screen.dart';
import 'package:adfoot/screens/setting_screen.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isOnline = true;
  bool _hasHandledArguments = false;

  StreamSubscription<bool>? _connectivitySub;

  final UserController userController = Get.find<UserController>();
  final ChatController chatController = Get.find<ChatController>();

  final List<Widget> _screens = <Widget>[
    const HomeScreen(),
    OffreScreen(),
    const EventListScreen(),
    const ConversationsScreen(),
    SettingsScreen(),
  ];

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

  void _listenConnectivity() {
    _connectivitySub = ConnectivityService().connectionStream.listen(
      (connected) {
        if (!mounted) return;
        setState(() => _isOnline = connected);
      },
      onError: (_) {},
    );

    ConnectivityService().checkInitialConnection().then((connected) {
      if (!mounted) return;
      setState(() => _isOnline = connected);
    }).catchError((_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_hasHandledArguments) {
      return;
    }

    final args = Get.arguments;
    if (args is int) {
      _selectedIndex = args;
    } else if (args is Map) {
      _selectedIndex = args['tab'] ?? 0;
    }

    _hasHandledArguments = true;
  }

  void _onItemTapped(int index) {
    HapticFeedback.selectionClick();

    if (index == 3) {
      chatController.markAllAsReadLocal();
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildHomeIcon({required bool active}) {
    final icon = active ? Icons.home_rounded : Icons.home_outlined;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        _NavIconShell(active: active, child: Icon(icon)),
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
    return Obx(() {
      final appUser = userController.user;
      final unread = chatController.totalUnread;

      if (appUser == null) {
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      return Scaffold(
        body: _screens[_selectedIndex],
        bottomNavigationBar: SafeArea(
          top: false,
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
                    colors: <Color>[
                      AdColors.surfaceAlt.withValues(alpha: 0.9),
                      AdColors.surface.withValues(alpha: 0.95),
                    ],
                  ),
                  border: Border(
                    top: BorderSide(
                      color: AdColors.divider.withValues(alpha: 0.9),
                      width: 1.2,
                    ),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: BottomNavigationBar(
                  backgroundColor: Colors.transparent,
                  selectedItemColor: AdColors.brand,
                  unselectedItemColor: AdColors.onSurfaceMuted,
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
                  items: <BottomNavigationBarItem>[
                    BottomNavigationBarItem(
                      icon: _buildHomeIcon(active: false),
                      activeIcon: _buildHomeIcon(active: true),
                      label: 'Accueil',
                    ),
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.local_offer_outlined),
                      activeIcon: Icon(Icons.local_offer_rounded),
                      label: 'Offres',
                    ),
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.event_outlined),
                      activeIcon: Icon(Icons.event_available_rounded),
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
                      activeIcon: Icon(Icons.settings_rounded),
                      label: 'Outils',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
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
      children: <Widget>[
        _NavIconShell(active: active, child: Icon(baseIcon)),
        if (unread > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const <BoxShadow>[
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

class _NavIconShell extends StatelessWidget {
  final Widget child;
  final bool active;

  const _NavIconShell({
    required this.child,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: active ?
            AdColors.brand.withValues(alpha: 0.18) :
            Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ?
              AdColors.brand.withValues(alpha: 0.35) :
              Colors.transparent,
          width: 1,
        ),
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(
                  color: AdColors.brand.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: child,
    );
  }
}
