import 'dart:async';
import 'dart:ui';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/connectivity_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/screens/conversation_screen.dart';
import 'package:adfoot/screens/home_screen.dart';
import 'package:adfoot/screens/add_video.dart';
import 'package:adfoot/screens/event_form_screen.dart';
import 'package:adfoot/screens/offres_form.dart';
import 'package:adfoot/screens/opportunities_screen.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/screens/terms_acceptance_screen.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/legal/terms_acceptance_service.dart';
import 'package:adfoot/services/notification_route.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:adfoot/services/notifications.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/widgets/ad_avatar.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
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

  final TermsAcceptanceService _termsService = TermsAcceptanceService();

  /// Which terms this screen currently requires.
  ///
  /// Starts at the version compiled into the build, not at "unknown": gating
  /// on a config that has not loaded yet would put every user behind a
  /// spinner on every cold start, and a network failure would lock the app.
  /// The remote value only ever tightens the requirement, and it arrives a
  /// moment later.
  TermsConfig _termsConfig = TermsConfig.bundled;

  final UserController userController = Get.find<UserController>();
  final ChatController chatController = Get.find<ChatController>();
  final AuthController _authController = Get.find<AuthController>();

  /// Where the tapped notification wants the Carrière screen to open.
  ///
  /// The screen is built fresh on every tab change, so a plain `initialTab`
  /// would be read once and never again. The serial is what makes a second
  /// request for the same tab still count as a request.
  int _opportunitiesTab = 0;
  int _opportunitiesTabSerial = 0;

  /// The four destinations, in bar order.
  ///
  /// `Outils` is not among them. It is a settings screen — Compte,
  /// Confidentialité, Sécurité, Suppression — and settings are visited
  /// rarely, while a profile is what a player checks constantly and what a
  /// recruiter's whole workflow ends on. The profile used to be reachable
  /// only through the avatar on the *home* app bar, which meant that from
  /// Offres, Events or Chat there was no way to your own profile at all
  /// without going back to the feed first. They have swapped places: Profil
  /// is a destination, Outils is one tap inside it.
  static const int _homeTab = 0;
  static const int _opportunitiesDestination = 1;
  static const int _chatTab = 2;
  static const int _profileTab = 3;

  Widget _destination(int index, AppUser user) {
    switch (index) {
      case _opportunitiesDestination:
        return OpportunitiesScreen(
          initialTab: _opportunitiesTab,
          tabRequestSerial: _opportunitiesTabSerial,
          showTalentSearch: isOpportunityPublisherRole(user.role),
        );
      case _chatTab:
        return const ConversationsScreen();
      case _profileTab:
        return ProfileScreen(uid: user.uid, isReadOnly: false);
      case _homeTab:
      default:
        return const HomeScreen();
    }
  }

  /// Whether this account has anything to publish.
  ///
  /// A player publishes videos; a club, a recruiter or an agent publishes
  /// offers and events. A fan publishes nothing, and gets no button — a
  /// disabled one would be worse than none.
  bool _canPublish(AppUser user) =>
      normalizeUserRole(user.role) == 'joueur' ||
      isOpportunityPublisherRole(user.role);

  /// Bar slots, as destination indices, with `null` for the publish action.
  ///
  /// The action sits in the middle because that is where a thumb rests and
  /// because the video surface has no room left for it: top is chrome, right
  /// is the action rail, bottom-left is the metadata. On an immersive feed
  /// the create action belongs to the navigation, not to the screen.
  List<int?> _barSlots(AppUser user) {
    if (!_canPublish(user)) {
      return const <int?>[_homeTab, _opportunitiesDestination, _chatTab, _profileTab];
    }
    return const <int?>[
      _homeTab,
      _opportunitiesDestination,
      null,
      _chatTab,
      _profileTab,
    ];
  }

  @override
  void initState() {
    super.initState();
    _listenConnectivity();
    _listenNotificationRoutes();
    unawaited(userController.ensureCurrentUserHydrated());
    unawaited(_refreshTermsConfig());
  }

  /// Picks up a terms version raised server-side since this build shipped.
  ///
  /// Best effort by design: TermsAcceptanceService never throws and falls back
  /// to the bundled version, so a failure here leaves the gate exactly as the
  /// build defined it rather than closing it on everyone.
  Future<void> _refreshTermsConfig() async {
    final config = await _termsService.fetchConfig();
    if (!mounted || config.requiredVersion == _termsConfig.requiredVersion) {
      return;
    }
    setState(() => _termsConfig = config);
  }

  Future<void> _acceptTerms() async {
    await userController.acceptTerms(_termsConfig.requiredVersion);
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
        _openOpportunities(tab: 0);
      case NotificationDestination.events:
        _openOpportunities(tab: 1);
      case NotificationDestination.conversations:
        _selectTab(_chatTab);
    }
  }

  void _selectTab(int index) {
    if (!mounted || _selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  /// Keeps a requested tab inside the destinations this bar actually has.
  ///
  /// The bar used to hold five: Accueil, Offres, Events, Chat, Outils. Callers
  /// still exist that were written against those indices — `offres_form`
  /// navigates to `/main` with `tab: 1`, which now means Carrière and happens
  /// to be right — and a payload from an older or newer build can name a
  /// destination that is not there. Falling back to Accueil is the honest
  /// answer; landing on nothing is not.
  int _safeDestination(int value) {
    if (value < _homeTab || value > _profileTab) {
      return _homeTab;
    }
    return value;
  }

  /// Opens Carrière on one of its two tabs.
  ///
  /// Offres and Événements were two destinations holding, on
  /// adfoot-production, one offer and two events between them — forty percent
  /// of the navigation bar for three documents. They are also the same thing
  /// seen twice: an opportunity published by a club, a recruiter or an agent
  /// for a player to answer. One destination, two tabs, and the slot that
  /// frees pays for the publish action the bar never had.
  void _openOpportunities({required int tab}) {
    if (!mounted) return;
    setState(() {
      _selectedIndex = _opportunitiesDestination;
      _opportunitiesTab = tab;
      _opportunitiesTabSerial++;
    });
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

    // Read defensively. These arguments come from notification payloads,
    // share links and the login screen, so `tab` is not guaranteed to be an
    // int — and `args['tab'] ?? 0` assigned whatever was there straight into
    // an int field, which throws inside didChangeDependencies and takes the
    // whole shell down to a red screen. A wrong tab is recoverable; this was
    // not.
    final args = Get.arguments;
    if (args is int) {
      _selectedIndex = _safeDestination(args);
    } else if (args is Map) {
      final tab = args['tab'];
      if (tab is int) {
        _selectedIndex = _safeDestination(tab);
      }
    }

    _hasHandledArguments = true;
  }

  void _onBarItemTapped(int barIndex, AppUser user) {
    HapticFeedback.selectionClick();

    final slots = _barSlots(user);
    if (barIndex < 0 || barIndex >= slots.length) return;

    final destination = slots[barIndex];
    if (destination == null) {
      unawaited(_openPublishAction(user));
      return;
    }

    _selectTab(destination);
  }

  /// What "Publier" means for this account.
  ///
  /// Deliberately role-aware rather than player-only. A slot in the middle of
  /// the bar that serves one role out of five would be dead space for
  /// everyone else; one that means "add a video" to a player and "publish an
  /// opportunity" to a club earns its place for every account that can create
  /// anything at all.
  ///
  /// Never a destination: it opens, and hands the current tab back.
  Future<void> _openPublishAction(AppUser user) async {
    if (normalizeUserRole(user.role) == 'joueur') {
      await Get.to(() => const AddVideo());
      return;
    }
    if (!isOpportunityPublisherRole(user.role)) return;
    if (!mounted) return;

    await _showPublishOpportunitySheet();
  }

  Future<void> _showPublishOpportunitySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AdColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AdColors.divider,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.local_offer_rounded,
                  color: AdColors.brand,
                ),
                title: const Text(
                  'Publier une offre',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Un poste, un essai, une opportunité.'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openOpportunities(tab: 0);
                  unawaited(_openFormAndAnnounce(const OffreFormScreen()));
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.event_available_rounded,
                  color: AdColors.brand,
                ),
                title: const Text(
                  'Créer un événement',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Une détection, un tournoi, une date.'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openOpportunities(tab: 1);
                  unawaited(_openFormAndAnnounce(const EventFormScreen()));
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Opens a publication form and says what came of it.
  ///
  /// Both forms answer with a result — `OffreFormResult`, `EventFormResult` —
  /// and popping is what delivers it. `OffreScreen` and `EventListScreen`
  /// have always turned that into a "Offre publiée" banner, but they only see
  /// it when *they* opened the form; the sheet here dropped the future on the
  /// floor, so publishing announced nothing at all.
  ///
  /// That is now the normal path, not an edge case: the create button was
  /// removed from both embedded screens (they defer to the bar's Publier), so
  /// without this a publisher got no confirmation whatsoever — the form just
  /// closed, and nothing said the offer existed.
  ///
  /// [AdFeedback] rather than the screens' own banner because this is the
  /// shell: it does not own either screen's notice slot, and the overlay
  /// reads the same on whichever tab the user lands.
  Future<void> _openFormAndAnnounce(Widget form) async {
    final result = await Get.to<Object?>(() => form);
    if (!mounted || result == null) return;

    final (String title, String message, String kind) = switch (result) {
      OffreFormResult r => (r.title, r.message, r.kind),
      EventFormResult r => (r.title, r.message, r.kind),
      _ => ('', '', ''),
    };
    if (message.isEmpty) return;

    if (kind == 'info') {
      AdFeedback.info(title, message);
    } else {
      AdFeedback.success(title, message);
    }
  }

  /// Where the current destination sits in this account's bar.
  int _barIndexFor(int destination, AppUser user) {
    final index = _barSlots(user).indexOf(destination);
    return index < 0 ? 0 : index;
  }

  List<BottomNavigationBarItem> _buildBarItems(AppUser user, int unread) {
    return <BottomNavigationBarItem>[
      for (final slot in _barSlots(user))
        if (slot == null)
          _publishBarItem()
        else
          switch (slot) {
            // "Carrière", not "Opportunités".
            //
            // A fixed bar splits its width evenly, so on a 360 dp screen each
            // slot gets 72 dp. "Opportunités" measures about 74 dp in the
            // selected style (12 px, w800) — Material puts no ellipsis on a
            // bar label and the word has no break point, so it was simply
            // cut. One word of eight characters clears the slot with room to
            // spare, and both tabs under it — an offer to answer, a detection
            // to attend — are steps in a career.
            _opportunitiesDestination => const BottomNavigationBarItem(
              icon: Icon(Icons.local_offer_outlined),
              activeIcon: Icon(Icons.local_offer_rounded),
              label: 'Carrière',
            ),
            _chatTab => BottomNavigationBarItem(
              icon: _ChatIconWithBadge(unread: unread, active: false),
              activeIcon: _ChatIconWithBadge(unread: unread, active: true),
              label: 'Chat',
            ),
            _profileTab => BottomNavigationBarItem(
              icon: _buildProfileIcon(user: user, active: false),
              activeIcon: _buildProfileIcon(user: user, active: true),
              label: 'Profil',
            ),
            _ => BottomNavigationBarItem(
              icon: _buildHomeIcon(active: false),
              activeIcon: _buildHomeIcon(active: true),
              label: 'Accueil',
            ),
          },
    ];
  }

  /// The create action, styled as the one thing in the bar that is not a place.
  ///
  /// Labelled rather than a bare glyph: "+" is unambiguous to a player and
  /// means nothing to a club. One word that is true for both.
  BottomNavigationBarItem _publishBarItem() {
    // Boxed to the same height as every other glyph.
    //
    // The tiles of a BottomNavigationBar are a Row of centred Columns, so a
    // shorter icon does not sit lower — it drags its whole tile, label
    // included, off the line its neighbours share. This pill is 30 px tall
    // against the 34 px of [_NavIconShell], and those four pixels were
    // visible: the "+" and the word under it floated above Accueil and Chat.
    final icon = SizedBox(
      height: _navIconBox,
      child: Center(
        child: Container(
          width: 38,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AdColors.brand,
            borderRadius: BorderRadius.circular(AdRadius.md),
          ),
          child: const Icon(
            Icons.add_rounded,
            color: AdColors.brandOn,
            size: 22,
          ),
        ),
      ),
    );

    return BottomNavigationBarItem(
      icon: icon,
      activeIcon: icon,
      label: 'Publier',
      tooltip: 'Publier',
    );
  }

  /// The profile tab, wearing the user's own photo.
  ///
  /// A generic glyph says "a profile"; the photo says "yours", which is the
  /// difference between a destination and *your* destination — and it is the
  /// one tab whose content is different for every account.
  ///
  /// [AdAvatar] is what makes it safe to put a network image in a bar that
  /// rebuilds on every unread-count change: it caches to disk rather than
  /// refetching, and a photo whose Storage object is gone falls back instead
  /// of reporting itself to Crashlytics as a fatal error.
  ///
  /// The fallback is the glyph this replaced, not generated initials: two
  /// letters inside a 22 px circle are not legible, and the large avatar on
  /// the profile screen is where initials still earn their place.
  Widget _buildProfileIcon({required AppUser user, required bool active}) {
    // The bar grows its glyphs from 24 to 26 when selected
    // (`selectedIconTheme`), and an `IconTheme` does not reach a
    // `CircleAvatar` — so the same two steps are spelled out here, or this one
    // tab would sit still while its neighbours moved.
    final diameter = active ? 26.0 : 24.0;

    return _NavIconShell(
      active: active,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: AdAvatar(
          photoUrl: user.photoProfil,
          radius: diameter / 2,
          backgroundColor: active
              ? AdColors.brand.withValues(alpha: 0.24)
              : AdColors.onSurfaceMuted.withValues(alpha: 0.18),
          fallback: Icon(
            active ? Icons.person_rounded : Icons.person_outline_rounded,
            size: diameter * 0.66,
            color: active ? AdColors.brand : AdColors.onSurfaceMuted,
          ),
        ),
      ),
    );
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

      // Consent gate.
      //
      // Placed here rather than on a route of its own: every way into the
      // signed-in app lands on this shell — cold start, a tapped notification,
      // a shared video link — so gating the shell is what makes the gate
      // impossible to route around. It also re-evaluates on its own when the
      // user document changes, because this build already runs inside an Obx.
      if (!_termsConfig.isSatisfiedBy(appUser.acceptedTermsVersion)) {
        return TermsAcceptanceScreen(
          config: _termsConfig,
          onAccept: _acceptTerms,
          onSignOut: userController.signOut,
        );
      }

      return Scaffold(
        body: _destination(_selectedIndex, appUser),
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
                child: _NavBarTextScale(
                  child: BottomNavigationBar(
                    backgroundColor: Colors.transparent,
                    selectedItemColor: AdColors.brand,
                    unselectedItemColor: AdColors.onSurfaceMuted,
                    currentIndex: _barIndexFor(_selectedIndex, appUser),
                    onTap: (index) => _onBarItemTapped(index, appUser),
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
                    items: _buildBarItems(appUser, unread),
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

/// Keeps the bar's labels legible at any system text size.
///
/// `main.dart` deliberately honours the system setting up to 1.6x, which is
/// right for a body of text and wrong for this: a fixed bar divides its width
/// evenly, so five slots on a 360 dp screen get 72 dp each no matter how
/// large the type. Material puts no ellipsis on a bar label, and none of
/// these words has a break point, so past about 1.15x every one of them is
/// cut mid-word — "Accueil" included.
///
/// Narrowing the range here rather than in the theme keeps the concession
/// exactly where the constraint is. Every label is one short word paired with
/// an icon, and none of them is the only way to know what a tab does; the
/// screens they open scale fully.
class _NavBarTextScale extends StatelessWidget {
  const _NavBarTextScale({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = media.textScaler.scale(1).clamp(0.85, 1.15);

    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(scale)),
      child: child,
    );
  }
}

/// The height every glyph in the bar occupies, selected or not.
///
/// Fixed on purpose. `selectedIconTheme` grows the glyph from 24 to 26, and
/// the shell used to grow with it — so the icon row measured 36 px on four
/// tiles and 38 on the fifth, and the tiles being centred Columns, the label
/// of whichever tab was selected sat a pixel off its neighbours. Selection is
/// now expressed entirely inside a box of constant height: the pill grows,
/// the row does not move.
const double _navIconBox = 36;

class _NavIconShell extends StatelessWidget {
  final Widget child;
  final bool active;

  const _NavIconShell({required this.child, required this.active});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _navIconBox,
      child: Center(
        child: AnimatedContainer(
          duration: AdMotion.normal,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: active
                ? AdColors.brand.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AdRadius.md),
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
        ),
      ),
    );
  }
}
