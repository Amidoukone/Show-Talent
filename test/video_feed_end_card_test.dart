import 'dart:io';

import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/video_feed_end_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// A bounded catalogue reaches its end. Saying so is the feature.
///
/// adfoot-production held 14 ready videos on 2026-08-24 with a cap of 10 per
/// player, so the fil ends in a couple of minutes. A wall reads as a broken
/// app and a silent loop reads as a bug, so the last page says "you are up to
/// date" and offers the two actions that lead somewhere.
void main() {
  group('the end of the feed is a page, not a wall', () {
    testWidgets('it names the count and offers both actions', (tester) async {
      var refreshed = 0;
      var searched = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: VideoFeedEndCard(
            videoCount: 14,
            onRefresh: () async => refreshed++,
            onSearch: () => searched++,
          ),
        ),
      );

      expect(find.text(VideoUiStrings.feedEndTitle), findsOneWidget);
      expect(find.textContaining('14'), findsOneWidget);

      await tester.tap(find.text(VideoUiStrings.feedEndRefreshAction));
      await tester.pump();
      await tester.tap(find.text(VideoUiStrings.feedEndSearchAction));
      await tester.pump();

      expect(refreshed, 1);
      expect(searched, 1);
    });

    testWidgets('a single video is not described in the plural', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: VideoFeedEndCard(videoCount: 1)),
      );

      expect(find.textContaining('la seule vidéo'), findsOneWidget);
    });

    testWidgets('an action the host did not give is not shown', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: VideoFeedEndCard(videoCount: 3)),
      );

      expect(find.text(VideoUiStrings.feedEndRefreshAction), findsNothing);
      expect(find.text(VideoUiStrings.feedEndSearchAction), findsNothing);
    });
  });

  group('the page is wired into the feed it belongs to', () {
    late String pager;
    late String home;

    setUpAll(() {
      pager = _read('lib/widgets/video_feed_pager.dart');
      home = _read('lib/screens/home_screen.dart');
    });

    // An empty feed already has the host's own empty state, and "you are up
    // to date" is the wrong thing to say to somebody shown nothing.
    test('an empty feed never gets one', () {
      expect(
        pager,
        contains(
          'widget.endOfFeedBuilder != null && widget.videos.isNotEmpty',
        ),
      );
    });

    // Nothing may keep playing behind it. Writing the index past the last
    // tile is what makes every SmartVideoPlayer go passive.
    test('reaching it stops playback', () {
      final focus = pager.indexOf('Future<void> _focus(int index) async');
      expect(focus, isNonNegative);
      final body = pager.substring(focus, focus + 900);

      expect(body, contains('if (_isEndOfFeedIndex(index)) {'));
      expect(body, contains('widget.videoController.currentIndex.value = index;'));
      expect(body, contains('_videoManager.pauseAll(widget.contextKey)'));
      expect(
        body.indexOf('if (_isEndOfFeedIndex(index)) {'),
        lessThan(body.indexOf('if (index < 0 || index >= videos.length) return;')),
        reason: 'the end page is not a video and must be handled first',
      );
    });

    // hasMore flips inside a fetch that may add no video at all, so a plain
    // field left the host with nothing to rebuild on.
    test('the feed says when it is complete, observably', () {
      final controller = _read('lib/controller/video_controller.dart');
      expect(controller, contains('final hasMoreVideos = true.obs;'));
      expect(controller, contains('bool get hasMore => hasMoreVideos.value;'));
      expect(home, contains('!videoController.hasMoreVideos.value'));
      expect(home, contains('endOfFeedBuilder:'));
    });

    // Search results are an answer to a question, not a fil to exhaust.
    test('a search never ends on it', () {
      expect(home, contains('!_isSearchActive && !videoController.hasMoreVideos.value'));
    });
  });
}
