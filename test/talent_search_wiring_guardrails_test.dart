import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Where the talent search hangs, and who sees it.
void main() {
  final opportunities = _read('lib/screens/opportunities_screen.dart');
  final main = _read('lib/screens/main_screen.dart');
  final screen = _read('lib/screens/talent_search_screen.dart');

  test('the Joueurs tab is added last', () {
    // Notifications open this screen by index — 0 is Offres, 1 is Événements.
    // Inserting a tab before them would land an event notification on another
    // page, which is the kind of break nobody attributes to a new tab.
    final offres = opportunities.indexOf("Tab(text: 'Offres')");
    final events = opportunities.indexOf("Tab(text: 'Événements')");
    final players = opportunities.indexOf("Tab(text: 'Joueurs')");

    expect(offres, greaterThan(-1));
    expect(events, greaterThan(offres));
    expect(players, greaterThan(events));
  });

  test('the tab count and the clamp move together', () {
    // A clamp left at a fixed 1 would silently swallow a request for the third
    // tab, and a length left at 2 would throw on it.
    expect(opportunities, contains('int get _tabCount =>'));
    expect(opportunities, contains('length: _tabCount,'));
    expect(opportunities, contains('value.clamp(0, _tabCount - 1)'));
  });

  test('only the roles that recruit get the tab', () {
    // A player has no use for a player search, and the tab would cost them a
    // third of the bar for nothing.
    expect(
      main,
      contains('showTalentSearch: isOpportunityPublisherRole(user.role)'),
    );
    expect(opportunities, contains('if (widget.showTalentSearch)'));
  });

  test('a failed search says so instead of showing an empty list', () {
    // A missing index answers `failed-precondition`; swallowed, it looks
    // exactly like "no player matches". They are not the same information for
    // a recruiter, and the second one is a lie.
    expect(screen, contains('_error ='));
    expect(screen, contains('Recherche indisponible'));
    expect(screen, contains('Aucun joueur ne correspond'));
  });

  test('the screen asks the repository rather than filtering itself', () {
    expect(screen, contains('_repository.search(_query)'));
    // Hydrating players to filter them on the phone is the thing this replaces.
    expect(screen, isNot(contains('fetchSearchablePlayers')));
  });
}
