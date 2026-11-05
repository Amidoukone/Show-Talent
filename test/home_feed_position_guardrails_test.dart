import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Leaving the Accueil tab used to send the user back to the top of the feed.
///
/// `MainScreen` swaps its body between destinations rather than keeping them in
/// an `IndexedStack`, so leaving the tab disposes `HomeScreen` and coming back
/// builds a new one. The fix was not to keep the screen alive: an `IndexedStack`
/// would hold this feed's native players next to the profile tab's, and
/// `VideoManager._globalMaxActive` exists because production ran out of
/// MediaCodec instances doing exactly that (two logged errors, 2026-08-22 and
/// 2026-08-23).
///
/// The index was never lost. It sits in the controller, which outlives the
/// screen. Only the pager was starting from zero.
void main() {
  late String home;

  setUpAll(() => home = _read('lib/screens/home_screen.dart'));

  group('the feed reopens where it was left', () {
    test('the pager is told where to start', () {
      expect(home, contains('int _restoredFeedIndex('));
      expect(home, contains('initialIndex: _restoredFeedIndex(feedVideos)'));
      expect(home, contains('videoController.currentIndex.value'));

      // Default is 0, which is what the feed did on every return.
      final pager = _read('lib/widgets/video_feed_pager.dart');
      expect(pager, contains('this.initialIndex = 0,'));
    });

    test('a search index is never restored into the feed', () {
      final start = home.indexOf('int _restoredFeedIndex(');
      expect(start, isNonNegative);
      final body = home.substring(start, start + 500);

      expect(body, contains('if (_isSearchActive || feedVideos.isEmpty) return 0;'));
      // -1 is the controller's "nothing selected", not a position.
      expect(body, contains('if (current <= 0) return 0;'));
      expect(body, contains('.clamp(0, feedVideos.length - 1)'));
    });
  });

  group('what makes it work must not be tidied away', () {
    // This is the real hazard. The persistence rests on HomeScreen never
    // releasing its controller, which reads like an oversight -- and someone
    // "fixing" the ref count would silently send the feed back to the top and
    // refetch it on every tab change.
    test('HomeScreen keeps the home video controller across rebuilds', () {
      expect(home, contains("contextKey: 'home',"));
      expect(home, contains('permanent: true,'));
      expect(
        home,
        isNot(contains('releaseVideoController')),
        reason: 'releasing it loses the feed and the index it carries',
      );
      expect(
        home,
        contains('deliberately *not* released here'),
        reason: 'the next reader must not take this for an oversight',
      );
    });

    // The players are a separate question from the controller, and for a
    // context that opts in (Home, the only one as of 2026-11) the two are no
    // longer treated identically: the one actually on screen survives the
    // tab change (instant resume, measured against the 105-session baseline
    // in docs/audit-lecture-video-2026-10-17.md), while every other player
    // this context held is still freed -- which is what returns their
    // decoders and is what `_globalMaxActive` relies on to stay meaningful.
    //
    // Opt-in, not the default: `releaseControllersExcept` does not forget a
    // context's preload/bandwidth/UI bookkeeping the way `disposeAllForContext`
    // does, which is fine for Home (one permanent context) but would
    // accumulate stale bookkeeping for a context created fresh per visit
    // (ProfileVideoScrollView) -- see VideoFocusOrchestrator.preserveActiveOnDispose.
    test(
        'the pager can release every player except the one on screen, and '
        'Home is the one context that asks for it', () {
      final pager = _read('lib/widgets/video_feed_pager.dart');
      expect(pager, contains('_orchestrator.onDispose()'));

      final orchestrator =
          _read('lib/videos/domain/video_focus_orchestrator.dart');
      expect(
        orchestrator,
        contains('releaseControllersExcept(contextKey, _lastFocusedUrl)'),
      );
      expect(
        orchestrator,
        contains('if (!preserveActiveOnDispose) {'),
        reason: 'the full teardown must stay the default; only an explicit '
            'opt-in may skip it',
      );

      final home = _read('lib/screens/home_screen.dart');
      expect(home, contains('preserveActiveOnDispose: true'));

      final profileVideoView = _read('lib/screens/profil_video_scrollview.dart');
      expect(
        profileVideoView,
        isNot(contains('preserveActiveOnDispose')),
        reason: 'a fresh contextKey per profile visited must keep the full, '
            'immediate cleanup -- it has nothing to gain from the '
            'optimization and would accumulate stale bookkeeping instead',
      );
    });

    // The alternative that was considered and rejected.
    test('the shell still builds one destination at a time', () {
      final main = _read('lib/screens/main_screen.dart');
      expect(main, contains('body: _destination(_selectedIndex, appUser)'));
      expect(
        main,
        isNot(contains('IndexedStack')),
        reason: 'two live feeds would stack two player budgets',
      );
    });
  });
}
