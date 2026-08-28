import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The navigation bar decides what this app is about, and it used to say the
/// wrong thing.
///
/// adfoot-production on 2026-08-24: 17 accounts — 11 joueurs, 1 club, 2
/// agents, 1 recruteur, 1 fan — and 1 offre, 2 événements. Offres and Events
/// were two of five destinations holding three documents between them, while
/// Outils (a settings screen) was a destination and the profile was not.
void main() {
  late String main;

  setUpAll(() => main = _read('lib/screens/main_screen.dart'));

  group('what is a destination and what is not', () {
    // Settings are visited rarely; a profile constantly. And the profile was
    // reachable only through the avatar on the *home* app bar, so from
    // Offres, Events or Chat there was no way to your own profile without
    // going back to the feed first.
    test('Profil is a destination, Outils is not', () {
      expect(main, contains("label: 'Profil',"));
      expect(
        main,
        isNot(contains("label: 'Outils',")),
        reason: 'settings moved one tap inside the profile',
      );

      final profile = _read('lib/screens/profile_screen.dart');
      expect(profile, contains("tooltip: 'Outils',"));
      expect(profile, contains('Get.to(() => SettingsScreen())'));
    });

    // Two destinations for three documents, and they are the same thing seen
    // twice: an opportunity published by a club, a recruiter or an agent for
    // a player to answer.
    test('Offres and Events became one destination with two tabs', () {
      // "Carrière", not "Opportunités": a fixed bar gives each of five slots
      // 72 dp on a 360 dp screen, and "Opportunités" measures about 74 dp in
      // the selected style. Material puts no ellipsis on a bar label and the
      // word has no break point, so it was cut mid-word.
      expect(main, contains("label: 'Carrière',"));
      expect(main, isNot(contains("label: 'Opportunités',")));
      expect(main, isNot(contains("label: 'Offres',")));
      expect(main, isNot(contains("label: 'Events',")));

      final screen0 = _read('lib/screens/opportunities_screen.dart');
      expect(
        screen0,
        contains("title: 'Carrière',"),
        reason: 'the bar and the header it opens must agree',
      );

      final screen = _read('lib/screens/opportunities_screen.dart');
      expect(screen, contains("Tab(text: 'Offres')"));
      expect(screen, contains("Tab(text: 'Événements')"));
      expect(screen, contains('OffreScreen(showAppBar: false)'));
      expect(screen, contains('EventListScreen(showAppBar: false)'));
    });

    // MainScreen builds one screen at a time, so the two have never been
    // alive together. A plain TabBarView would change that: two controllers,
    // two sets of Firestore listeners, for a tab nobody has opened.
    test('the unopened tab is not built', () {
      final screen = _read('lib/screens/opportunities_screen.dart');
      expect(screen, contains('final Set<int> _visitedTabs'));
      expect(screen, contains('if (!_visitedTabs.contains(index))'));
      expect(screen, contains('return const SizedBox.shrink();'));
    });
  });

  group('the profile tab wears the user photo', () {
    // A generic glyph says "a profile"; the photo says "yours" — and it is
    // the one tab whose content differs for every account.
    test('it renders the account photo, not a glyph', () {
      expect(main, contains('Widget _buildProfileIcon('));
      expect(main, contains('photoUrl: user.photoProfil,'));
      expect(main, contains('_buildProfileIcon(user: user, active: true)'));
    });

    // The bar rebuilds on every unread-count change. A bare NetworkImage
    // there refetches each time and, worse, routes a dead Storage object to
    // FlutterError.onError — which this app books as a fatal crash.
    test('it goes through AdAvatar, not a raw network image', () {
      expect(main, contains('AdAvatar('));
      expect(
        main,
        isNot(contains('NetworkImage(')),
        reason: 'an unlistened image failure is reported as a crash',
      );
      expect(
        main,
        contains('fallback: Icon('),
        reason: 'no photo and a failed photo must look the same',
      );
    });

    // selectedIconTheme grows the other glyphs from 24 to 26, and an
    // IconTheme does not reach a CircleAvatar.
    test('it grows with its neighbours when selected', () {
      expect(main, contains('final diameter = active ? 26.0 : 24.0;'));
      expect(main, contains('radius: diameter / 2,'));
    });
  });

  group('the publish action', () {
    // A slot serving one role out of five would be dead space for everyone
    // else. One that means "add a video" to a player and "publish an
    // opportunity" to a club earns its place for every account that can
    // create anything.
    test('it means different things to different roles', () {
      expect(main, contains('Future<void> _openPublishAction('));
      expect(main, contains("normalizeUserRole(user.role) == 'joueur'"));
      expect(main, contains('Get.to(() => const AddVideo())'));
      expect(main, contains('isOpportunityPublisherRole(user.role)'));
      expect(main, contains('_showPublishOpportunitySheet()'));
      expect(main, contains("'Publier une offre'"));
      expect(main, contains("'Créer un événement'"));
    });

    // A fan publishes nothing. A disabled button would be worse than none.
    test('an account with nothing to create gets no slot', () {
      expect(main, contains('bool _canPublish('));

      final slots = main.indexOf('List<int?> _barSlots(');
      expect(slots, isNonNegative);
      final body = main.substring(slots, slots + 600);
      expect(body, contains('if (!_canPublish(user))'));
      expect(
        body,
        contains('_homeTab, _opportunitiesDestination, _chatTab, _profileTab'),
        reason: 'four entries, no null slot',
      );
    });

    // It opens and hands the current tab back; it never becomes the selected
    // destination.
    test('it is an action, not a place', () {
      final tap = main.indexOf('void _onBarItemTapped(');
      expect(tap, isNonNegative);
      final body = main.substring(tap, tap + 500);

      expect(body, contains('if (destination == null)'));
      expect(body, contains('_openPublishAction(user)'));
      expect(
        body,
        contains('return;'),
        reason: 'the action must not fall through to _selectTab',
      );
    });

    // Labelled rather than a bare glyph: "+" is unambiguous to a player and
    // means nothing to a club.
    test('it is labelled', () {
      expect(main, contains("label: 'Publier',"));
    });
  });

  group('notifications still land somewhere real', () {
    // The three routes pointed at fixed indices of the old five-tab bar.
    test('offers and events open their tab of Opportunités', () {
      expect(main, contains('_openOpportunities(tab: 0)'));
      expect(main, contains('_openOpportunities(tab: 1)'));
      expect(main, contains('_selectTab(_chatTab)'));
    });

    // The screen is rebuilt rather than recreated on a tab change, so
    // initialTab alone would be read once in initState and never again — and
    // a second notification for the same tab still has to land.
    test('a repeated request for the same tab still counts', () {
      final screen = _read('lib/screens/opportunities_screen.dart');
      expect(screen, contains('final int tabRequestSerial;'));
      expect(screen, contains('void didUpdateWidget('));
      expect(
        screen,
        contains('if (oldWidget.tabRequestSerial == widget.tabRequestSerial) return;'),
      );
      expect(main, contains('_opportunitiesTabSerial++'));
    });
  });

  group('publishing says what happened', () {
    // Both forms answer with a result -- OffreFormResult, EventFormResult --
    // and popping is what delivers it. The sheet dropped the future on the
    // floor, so publishing announced nothing.
    //
    // That is the normal path, not an edge case: the create button was
    // removed from both embedded screens in favour of this one, so a
    // publisher got no confirmation at all -- the form simply closed.
    test('the sheet awaits the form result instead of dropping it', () {
      expect(main, contains('Future<void> _openFormAndAnnounce('));
      expect(
        main,
        isNot(contains('unawaited(Get.to(() => const OffreFormScreen()))')),
        reason: 'the result carries the confirmation',
      );
      expect(
        main,
        isNot(contains('unawaited(Get.to(() => const EventFormScreen()))')),
      );
      expect(
        main,
        contains('unawaited(_openFormAndAnnounce(const OffreFormScreen()))'),
      );
      expect(
        main,
        contains('unawaited(_openFormAndAnnounce(const EventFormScreen()))'),
      );
    });

    // The shell does not own either screen's notice slot, so it announces
    // through the overlay -- which also reads the same whichever tab the
    // user lands on.
    test('it announces both result types', () {
      expect(main, contains('OffreFormResult r =>'));
      expect(main, contains('EventFormResult r =>'));
      expect(main, contains('AdFeedback.success(title, message)'));
      expect(main, contains('AdFeedback.info(title, message)'));
    });
  });

  group('the bar holds its line', () {
    // selectedIconTheme grows the glyph from 24 to 26. The shell grew with
    // it, so the icon row measured 36 px on four tiles and 38 on the fifth --
    // and the tiles being centred Columns, the selected label sat off its
    // neighbours. The publish pill was worse: 30 px against 36.
    test('every glyph occupies the same height, selected or not', () {
      expect(main, contains('const double _navIconBox = 36;'));

      final shell = main.indexOf('class _NavIconShell');
      expect(shell, isNonNegative);
      final body = main.substring(shell);
      expect(body, contains('height: _navIconBox,'));

      final publish = main.indexOf('BottomNavigationBarItem _publishBarItem()');
      expect(publish, isNonNegative);
      expect(
        main.substring(publish, publish + 900),
        contains('height: _navIconBox,'),
        reason: 'the action sits on the same line as the destinations',
      );
    });

    // main.dart honours the system text size up to 1.6x, which is right for
    // a body of text and wrong for a fixed bar: the slots stay 72 dp however
    // large the type, and Material puts no ellipsis on a bar label.
    test('label scaling is bounded, and only here', () {
      expect(main, contains('class _NavBarTextScale'));
      expect(main, contains('.clamp(0.85, 1.15)'));
      expect(main, contains('child: _NavBarTextScale('));

      final app = _read('lib/main.dart');
      expect(
        app,
        contains('.clamp(0.85, 1.6)'),
        reason: 'the rest of the app must keep scaling for low vision',
      );
    });
  });

  group('a route intent is acted on once', () {
    // The shell swaps its body between destinations rather than keeping them
    // in an IndexedStack, so leaving a tab disposes its State and coming back
    // builds a new one -- while Get.arguments stays set for the life of the
    // route. A `bool _hasHandled` field cannot help: it is the State itself
    // that is recreated.
    test('the screens inside the shell consume, not just read', () {
      final home = _read('lib/screens/home_screen.dart');
      expect(home, contains("RouteIntent.readOnce('home_playback')"));
      expect(
        home,
        isNot(contains('final args = Get.arguments;')),
        reason: 'a shared video link jumped the feed back on every visit',
      );

      final offers = _read('lib/screens/offre_screen.dart');
      expect(offers, contains("RouteIntent.readOnce('offer_notice')"));
      expect(
        offers,
        isNot(contains('final args = Get.arguments;')),
        reason: '"Offre publiee" was announced again on every visit',
      );
    });

    // Keyed per consumer, so two screens reading different parts of the same
    // arguments do not consume each other's; cleared when the arguments
    // change identity, so a genuinely new intent is always delivered.
    test('the ledger is per consumer and resets on the next navigation', () {
      final intent = _read('lib/services/route_intent.dart');
      expect(intent, contains('static Map<dynamic, dynamic>? readOnce('));
      expect(intent, contains('if (!identical(arguments, _argumentsIdentity))'));
      expect(intent, contains('_consumed.clear();'));
      expect(intent, contains('if (!_consumed.add(key))'));
    });

    // The shell keeps reading Get.arguments directly -- its own State is not
    // recreated on a tab change -- but the value is not to be trusted: it
    // comes from notification payloads and share links, and assigning a
    // non-int straight into an int field throws inside
    // didChangeDependencies and takes the whole shell to a red screen.
    test('the shell reads its tab defensively', () {
      expect(main, contains('if (tab is int) {'));
      expect(main, isNot(contains("_selectedIndex = args['tab'] ?? 0;")));
      expect(main, contains('int _safeDestination(int value)'));
    });
  });

  group('creation has one home', () {
    // Two create buttons fifty pixels apart is worse than the extra tap
    // either saves, and the publishers create rarely: one offer and two
    // events in the whole of adfoot-production.
    test('the embedded screens drop their own create button', () {
      final offers = _read('lib/screens/offre_screen.dart');
      final events = _read('lib/screens/event_list_screen.dart');

      expect(offers, contains('widget.showAppBar\n          ? _buildFloatingButton()'));
      expect(events, contains('widget.showAppBar\n          ? _buildFloatingActionButton('));
    });

    // Standing on their own they keep it, so nothing changes for a caller
    // that shows either screen outside the host.
    test('standalone they keep it', () {
      final offers = _read('lib/screens/offre_screen.dart');
      expect(offers, contains('this.showAppBar = true'));
      expect(offers, contains('Widget _buildFloatingButton()'));
    });
  });
}
