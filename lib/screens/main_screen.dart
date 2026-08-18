import 'dart:async';
import 'dart:ui';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/connectivity_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/screens/conversation_screen.dart';
import 'package:adfoot/screens/event_list_screen.dart';
import 'package:adfoot/screens/home_screen.dart';
import 'package:adfoot/screens/offre_screen.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/screens/setting_screen.dart';
import 'package:adfoot/services/notification_route.dart';
import 'package:adfoot/services/notifications.dart';
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
  StreamSubscription<NotificationRoute>? _notificationRouteSub;

  final UserController userController = Get.find<UserController>();
  final ChatController chatController = Get.find<ChatController>();
  final AuthController _authController = Get.find<AuthController>();

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
    _listenNotificationRoutes();
    unawaited(userController.ensureCurrentUserHydrated());
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _notificationRouteSub?.cancel();
    super.dispose();
  }

  /// Turns a tapped notification into a destination.
  ///
  /// The shell is the right owner: it is the first widget that exists after
  /// authentication, so it can navigate, and it already holds the tab index a
  /// message/offer/event notification needs to reach.
  void _listenNotificationRoutes() {
    _notificationRouteSub = NotificationService.routeTaps.listen(
      _openNotificationRoute,
      onError: (_) {},
    );

    // A tap that launched the app from a killed state was captured during
    // bootstrap, long before any screen could handle it. Replay it once the
    // first frame is on screen, so the destination pushes over the shell
    // rather than racing it.
    final pending = NotificationService.takePendingRoute();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openNotificationRoute(pending);
      });
    }
  }

  void _openNotificationRoute(NotificationRoute route) {
    if (!mounted) return;

    switch (route.destination) {
      case NotificationDestination.none:
        return;
      case NotificationDestination.ownProfile:
        // Read the uid from auth, not from the hydrated profile. The common
        // case for this route is a cold start: the phone was in a pocket, the
        // "video approuvee" notification arrived, and the tap launches the app
        // from a killed state. At that moment `userController.user` is still
        // being fetched, so keying off it dropped the route in silence and
        // landed the author on the feed — the one destination that does not
        // show the video they were just told about. ProfileScreen loads the
        // profile itself; all it needs is the uid.
        final uid = _authController.currentUid;
        if (uid == null || uid.isEmpty) {
          // Genuinely signed out. Nothing to open.
          return;
        }
        unawaited(Get.to(() => ProfileScreen(uid: uid, isReadOnly: false)));
      case NotificationDestination.offers:
        _selectTab(1);
      case NotificationDestination.events:
        _selectTab(2);
      case NotificationDestination.conversations:
        _selectTab(3);
    }
  }

  void _selectTab(int index) {
    if (!mounted || _selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  void _listenConnectivity() {
    _connectivitySub = ConnectivityService().connectionStream.listen((
      connected,
    ) {
      if (!mounted) return;
      setState(() => _isOnline = connected);
    }, onError: (_) {});

    ConnectivityService()
        .checkInitialConnection()
        .then((connected) {
          if (!mounted) return;
          setState(() => _isOnline = connected);
        })
        .catchError((_) {});
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
            child: CircleAvatar(radius: 4, backgroundColor: AdColors.error),
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
        final isLoading = userController.isUserHydrationPending;
        final hasAttempted = userController.hasAttemptedHydration;

        // Self-heal. Reaching this branch with no attempt in flight and none
        // ever completed used to leave a bare spinner running forever, with
        // no code path left that would ever replace it. Kick a hydration
        // instead so the screen always converges on a profile or on an
        // actionable error.
        if (!isLoading && !hasAttempted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(userController.ensureCurrentUserHydrated());
          });
        }

        // Only spin while something is actually running. Once an attempt has
        // settled without producing a profile there is always a message to
        // show (UserController.ensureCurrentUserHydrated guarantees it), so
        // the user gets an explanation and a Réessayer button rather than an
        // endless loader.
        final message = isLoading || !hasAttempted
            ? ''
            : (userController.sessionLoadMessage.trim().isEmpty
                  ? 'Impossible de charger le profil. '
                        'Réessayez dans quelques instants.'
                  : userController.sessionLoadMessage);

        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: message.isEmpty
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.account_circle_outlined,
                          size: 56,
                          color: AdColors.onSurfaceMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Profil indisponible',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AdColors.onSurfaceMuted,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: isLoading
                              ? null
                              : () => userController.ensureCurrentUserHydrated(
                                  force: true,
                                ),
                          icon: isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
            ),
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
                      icon: _ChatIconWithBadge(unread: unread, active: false),
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

  const _ChatIconWithBadge({required this.unread, required this.active});

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
                color: AdColors.error,
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

  const _NavIconShell({required this.child, required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: active
            ? AdColors.brand.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? AdColors.brand.withValues(alpha: 0.35)
              : Colors.transparent,
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
