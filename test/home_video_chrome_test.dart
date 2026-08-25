import 'dart:io';

import 'package:adfoot/utils/publisher_headline.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The home screen is an immersive video feed with chrome laid over it. These
/// pin the four decisions that chrome makes, because every one of them was
/// made differently before.
void main() {
  group('the video says who is in it', () {
    // A recruiter watching a clip is answering one question — is this player
    // worth my attention — and the poste answers it. "joueur" does not: the
    // surrounding context already says it is a player. The fields have been
    // on AppUser and indexed for search all along; the video was the one
    // place they were missing.
    test('a player is badged by poste, not by account role', () {
      expect(
        PublisherHeadline.badge(role: 'joueur', position: 'Attaquant'),
        'Attaquant',
      );
    });

    // adfoot-production, 2026-08-24: one of the three publishing accounts has
    // no position at all. It falls back rather than showing an empty badge.
    test('a player without a poste keeps the role', () {
      expect(PublisherHeadline.badge(role: 'joueur', position: null), 'joueur');
      expect(PublisherHeadline.badge(role: 'joueur', position: '   '), 'joueur');
    });

    // For a club or a recruiter the role *is* the fact that matters: a clip
    // published by a club is a different thing from the same clip published
    // by the player in it.
    test('every other account keeps its role', () {
      expect(
        PublisherHeadline.badge(role: 'club', position: 'Attaquant'),
        'club',
      );
      expect(
        PublisherHeadline.badge(role: 'recruteur', position: 'Milieu'),
        'recruteur',
      );
    });

    test('the detail line joins what is known and nothing else', () {
      expect(
        PublisherHeadline.details(
          club: 'ASEC Mimosas',
          team: null,
          city: 'Abidjan',
        ),
        'ASEC Mimosas · Abidjan',
      );
      expect(
        PublisherHeadline.details(club: null, team: null, city: 'Abidjan'),
        'Abidjan',
      );
    });

    // No production profile carried a club or a ville on 2026-08-24, so the
    // common case today is nothing at all — and an empty row under a name
    // reads as a rendering bug.
    test('an unfilled profile produces no line at all', () {
      expect(
        PublisherHeadline.details(club: null, team: null, city: null),
        isEmpty,
      );
      expect(
        PublisherHeadline.details(club: '  ', team: '', city: '   '),
        isEmpty,
      );
    });

    // clubActuel is the current declaration, team the older field. One of
    // them, never both, or a profile that filled in each separately would
    // read "ASEC · ASEC".
    test('the two club fields never both appear', () {
      expect(
        PublisherHeadline.details(club: 'ASEC', team: 'ASEC', city: null),
        'ASEC',
      );
      expect(
        PublisherHeadline.details(club: null, team: 'Africa Sports', city: null),
        'Africa Sports',
      );
    });

    test('the overlay renders the line only when there is one', () {
      final overlay = _read('lib/widgets/video_metadata_overlay.dart');
      expect(overlay, contains('final String publisherDetails;'));
      expect(
        overlay,
        contains('if (hasPublisher && trimmedDetails.isNotEmpty)'),
      );

      final player = _read('lib/widgets/smart_video_player.dart');
      expect(player, contains('PublisherHeadline.badge('));
      expect(player, contains('PublisherHeadline.details('));
      expect(
        player,
        isNot(contains("publisherRole: publisher?.role ?? ''")),
        reason: 'the raw account role is what this replaced',
      );
    });
  });

  group('the chrome over the video', () {
    late String home;

    setUpAll(() => home = _read('lib/screens/home_screen.dart'));

    // The floatingActionButton slot belongs to an action. The chip is a
    // notification, and renting the slot for it meant the Scaffold's own FAB
    // positioning and transitions were driving a chip they know nothing
    // about — with a hand-rolled kToolbarHeight offset to undo them.
    test('the new-videos chip is not a floating action button', () {
      expect(
        home,
        isNot(contains('floatingActionButtonLocation:')),
        reason: 'the slot is free for a real action now',
      );
      expect(home, isNot(contains('floatingActionButton:')));
      expect(home, contains('Widget _buildPendingLiveVideosOverlay()'));
    });

    // An overlay the size of the screen sits between the thumb and the feed,
    // and whether it swallows a swipe then depends on which widgets in it
    // happen to hit-test. A strip pinned to the top edge cannot.
    test('the chip occupies a top strip, not the whole body', () {
      final stack = home.indexOf('Positioned.fill(child: _buildFeedBody())');
      expect(stack, isNonNegative);
      final body = home.substring(stack, stack + 1400);

      expect(body, contains('_buildPendingLiveVideosOverlay()'));
      expect(
        body,
        isNot(contains('Positioned.fill(child: _buildPendingLiveVideosOverlay())')),
        reason: 'filling the stack puts an overlay across every swipe',
      );
      expect(body, contains('top: 0,'));
    });

    // extendBodyBehindAppBar puts the body at y = 0, so the chip has to clear
    // the status bar *and* the bar. One expression that says so beats a
    // SafeArea wrapping a constant.
    test('the offset is computed, not assumed', () {
      expect(home, contains('double _pendingChipTopOffset(BuildContext context)'));
      expect(
        home,
        contains('MediaQuery.paddingOf(context).top + kToolbarHeight + 10'),
      );
    });

    // The tonal treatment was a step on the way; the button has since left
    // the app bar entirely. Publishing is the action that defines a player's
    // account, and it was in the least reachable corner of the screen, on one
    // tab only. It is in the navigation bar now — the thumb zone — because on
    // an immersive feed there is no room left anywhere else: top is chrome,
    // right is the action rail, bottom-left is the metadata.
    test('the app bar carries neither the create action nor the profile', () {
      final bar = home.indexOf('title: _buildVideoSearchLauncher()');
      expect(bar, isNonNegative);
      final barBlock = home.substring(bar, bar + 200);

      expect(barBlock, contains('actions: const [],'));
      expect(
        barBlock,
        isNot(contains('Icons.add_rounded')),
        reason: 'creation moved to the navigation bar',
      );
      expect(
        home,
        isNot(contains('_buildHomeProfileAvatar')),
        reason: 'the profile is a destination now, not an app bar action',
      );

      // The empty-feed state keeps its own "add a video" button: there is no
      // feed to compete with there, and it is the only thing on the screen.
      expect(
        home,
        contains('canPublish ? Icons.add_rounded : Icons.refresh_rounded'),
      );
    });

    // The body runs behind the app bar, so the card has to reserve the same
    // room every video tile's overlays do.
    test('the end-of-feed card clears the app bar', () {
      expect(home, contains('topInset: kToolbarHeight,'));

      final card = _read('lib/widgets/video_feed_end_card.dart');
      expect(card, contains('this.topInset = 0,'));
      expect(card, contains('AdSpacing.xl + topInset,'));
    });
  });
}
