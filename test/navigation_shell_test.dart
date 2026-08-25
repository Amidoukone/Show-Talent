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
      expect(main, contains("label: 'Opportunités',"));
      expect(main, isNot(contains("label: 'Offres',")));
      expect(main, isNot(contains("label: 'Events',")));

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
