import 'dart:io';

import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'video_local_state_test.dart' show makeVideo;

/// One vertical video feed, hosted by two screens.
///
/// There were three implementations — the home feed, the profile feed, and a
/// `video_feed_screen.dart` no screen opened — each with its own page
/// controller, index bookkeeping, haptics, orchestrator wiring and lifecycle
/// pausing. Nothing was obviously broken, which is exactly why the drift went
/// unnoticed: only one of the three loaded more videos as you scrolled, and
/// only one of the three prefetched thumbnails.
String _read(String path) => File(path).readAsStringSync();

/// The same file with its comments stripped.
///
/// Several of these files carry a note explaining what was removed and why —
/// naming the very symbol the assertion forbids. That history is worth more
/// than a literal string match, so the assertions look at code.
String _code(String path) => _read(path)
    .split('\n')
    .where((line) {
      final trimmed = line.trimLeft();
      return !trimmed.startsWith('//') && !trimmed.startsWith('///');
    })
    .join('\n');

Video withThumb(String id, String thumb) => Video(
  id: id,
  videoUrl: 'https://example.test/$id.mp4',
  thumbnailUrl: thumb,
  description: '',
  caption: '',
  profilePhoto: '',
  uid: 'author',
  status: 'ready',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('thumbnails are warmed for the list actually on screen', () {
    late VideoController controller;
    late List<String> warmed;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      warmed = <String>[];
      controller = VideoController(
        contextKey: 'pager-test',
        enableLiveStream: false,
        enableFeedFetch: false,
      );
      controller.setThumbnailPrefetcherForTests((url) async {
        warmed.add(url);
      });
    });

    // `prefetchThumbnailsAroundIndex` indexes into `videoList`. A search
    // result set and a profile's videos are different lists, so on those
    // surfaces it warmed the wrong thumbnails — and the home feed's search
    // branch, aware of that, skipped prefetching altogether.
    test('a list the controller does not own is still prefetched', () async {
      controller.replaceVideos([withThumb('feed', 'https://cdn/feed.jpg')]);
      warmed.clear();

      final searchResults = [
        withThumb('s0', 'https://cdn/s0.jpg'),
        withThumb('s1', 'https://cdn/s1.jpg'),
        withThumb('s2', 'https://cdn/s2.jpg'),
      ];

      controller.prefetchThumbnailsFor(searchResults, 1);
      await Future<void>.delayed(Duration.zero);

      expect(warmed, containsAll(['https://cdn/s1.jpg', 'https://cdn/s0.jpg']));
      expect(
        warmed,
        isNot(contains('https://cdn/feed.jpg')),
        reason: 'the feed is not what is on screen',
      );
    });

    test('an out-of-range centre warms nothing', () async {
      controller.prefetchThumbnailsFor([withThumb('a', 'https://cdn/a.jpg')], 7);
      await Future<void>.delayed(Duration.zero);

      expect(warmed, isEmpty);
    });

    test('an empty list warms nothing', () async {
      controller.prefetchThumbnailsFor(const <Video>[], 0);
      await Future<void>.delayed(Duration.zero);

      expect(warmed, isEmpty);
    });
  });

  group('surfacing buffered live videos', () {
    late VideoController controller;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      controller = VideoController(
        contextKey: 'pager-live-test',
        enableLiveStream: false,
        enableFeedFetch: false,
      );
    });

    // The predicate depends on where the user came *from*, which is why it
    // could not stay bundled with the write of the index: the pager owns the
    // index now, and the host still has to be able to ask the question.
    test('scrolling back to the top from further down is what triggers it',
        () async {
      controller.replaceVideos([makeVideo()]);

      expect(
        controller.shouldSurfacePendingLiveAt(previousIndex: 3, index: 0),
        isFalse,
        reason: 'nothing is buffered, and a scoped feed has no live stream',
      );
    });

    test('arriving at an index other than the top never triggers it', () {
      expect(
        controller.shouldSurfacePendingLiveAt(previousIndex: 0, index: 2),
        isFalse,
      );
    });
  });

  group('both feeds are the same feed', () {
    late String pager;
    late String home;
    late String profileFeed;

    setUpAll(() {
      pager = _read('lib/widgets/video_feed_pager.dart');
      home = _read('lib/screens/home_screen.dart');
      profileFeed = _read('lib/screens/profil_video_scrollview.dart');
    });

    test('neither screen builds its own PageView any more', () {
      for (final entry in {'home': home, 'profile': profileFeed}.entries) {
        expect(
          entry.value,
          isNot(contains('PageView.builder(')),
          reason: '${entry.key} must host the shared pager',
        );
        expect(entry.value, contains('VideoFeedPager('));
      }

      expect(pager, contains('PageView.builder('));
      expect(pager, contains('VideoFocusOrchestrator('));
      expect(pager, contains('HapticFeedback.selectionClick()'));
    });

    // The profile feed received a fixed snapshot of whatever the grid had
    // loaded and stopped there. ProfileController had paginated all along;
    // nothing was wired to it because only the home feed had a hook.
    test('the profile feed loads more as you reach the end', () {
      expect(profileFeed, contains('onRequestMore: _loadMoreProfileVideos'));
      expect(profileFeed, contains('profileController.fetchUserVideos('));
      expect(profileFeed, contains('profileController.hasMoreVideos'));
      expect(pager, contains('onRequestMore: widget.onRequestMore'));
    });

    test('the pager prefetches from what it renders', () {
      expect(
        pager,
        contains(
          'widget.videoController.prefetchThumbnailsFor(widget.videos, index)',
        ),
      );
    });

    // A delete, a refresh or a cleared search can leave the index past the
    // end of the list. Only the two scoped feeds guarded against it.
    test('the pager clamps an index the feed no longer has', () {
      expect(pager, contains('void _syncIndexWithFeedLength()'));
      // The last index is the last video, plus the end-of-feed page when the
      // feed has one — clamping to the last *video* would drop the user off
      // that page every time the list changed under it.
      expect(
        pager,
        contains('final lastIndex = length - 1 + (_hasEndOfFeedPage ? 1 : 0);'),
      );
      expect(pager, contains('_currentIndex.clamp(0, lastIndex)'));
    });

    // A programmatic jump must not be reported as a swipe: on the home feed
    // that could re-enter the very "new videos on top" flow that performed
    // the jump.
    test('a programmatic jump is not mistaken for a page change', () {
      expect(pager, contains('_silencedPageIndex'));
      expect(home, contains('void _jumpToPageSilently(int index) =>'));
    });
  });

  // Reported after the 1.0.7+22 build: every tile spinning with no playback
  // after adding a video, a slow first launch, videos apparently out of order,
  // and the profile feed dying outright. One cause underneath all four.
  group('a focus request is never lost', () {
    late String pager;

    setUpAll(() {
      pager = _read('lib/widgets/video_feed_pager.dart');
    });

    // The hosts ask for an index from a post-frame callback; the pager is
    // only built on the frame after that, so `_state` was still null and the
    // request evaporated. Nothing focused, no controller attached, every tile
    // spinning — while `videoController.currentIndex` named a page the user
    // was not on, so the visible tile believed it was not the active one and
    // refused to play. That mismatch is what looked like "wrong order".
    test('an index asked for before the pager exists is replayed', () {
      expect(pager, contains('int? _pendingIndex;'));

      final attach = pager.indexOf('void _attach(_VideoFeedPagerState state)');
      expect(attach, isNonNegative);
      final body = pager.substring(attach, attach + 400);
      expect(body, contains('state._applyPendingIndex(pending)'));

      for (final method in ['void jumpToPage(int index)',
                            'Future<void> activate(int index)']) {
        final start = pager.indexOf(method);
        expect(start, isNonNegative, reason: method);
        expect(
          pager.substring(start, start + 260),
          contains('_pendingIndex = index;'),
          reason: '$method must not be a silent no-op',
        );
      }
    });

    // Replaying the request as a `_jumpToPage` put the fault back. `_attach`
    // runs from initState, where the page controller either does not exist
    // yet or has just been constructed on `initialIndex`; with no clients
    // `_jumpToPage` moves `_currentIndex` and returns, leaving the page view
    // on a different page from the one every other part of the app believes
    // is current. That mismatch is the spinning tile.
    test('the page controller is built on the index we replayed', () {
      final initState = pager.indexOf('void initState()');
      final didUpdate = pager.indexOf('void didUpdateWidget', initState);
      expect(initState, isNonNegative);
      final body = pager.substring(initState, didUpdate);

      final attach = body.indexOf('widget.pagerController._attach(this);');
      final build = body.indexOf('_pageController = PageController(');
      expect(attach, isNonNegative);
      expect(build, isNonNegative);
      expect(
        attach,
        lessThan(build),
        reason: 'a replayed index must be able to become the opening page',
      );

      expect(pager, contains('bool _hasPageController = false;'));

      final apply = pager.indexOf('void _applyPendingIndex(int index)');
      expect(apply, isNonNegative);
      final applyBody = pager.substring(apply, apply + 420);
      expect(applyBody, contains('if (!_hasPageController)'));
      expect(applyBody, contains('_currentIndex = clamped;'));
    });

    // initState's post-frame callback focuses `_currentIndex` on its own. A
    // replay that focused as well landed inside the orchestrator's 120 ms
    // settle window: the first request was discarded as stale and the second
    // paid a delay a feed's first focus is meant never to pay.
    test('opening a feed focuses once', () {
      final attach = pager.indexOf('void _attach(_VideoFeedPagerState state)');
      expect(
        pager.substring(attach, attach + 400),
        isNot(contains('_focus(')),
        reason: 'initState already focuses what it opened on',
      );

      // The home feed asks for its opening index itself, from a post-frame
      // callback registered while the pager was still being built — so both
      // fire on the same frame, 0 ms apart, and cold start paid the settle
      // delay for a scroll nobody made. The pager's own request is a fallback
      // for hosts that do not ask.
      expect(pager, contains('bool _hasFocusedOnce = false;'));
      expect(pager, contains('if (!mounted || _hasFocusedOnce) return;'));

      final focus = pager.indexOf('Future<void> _focus(int index) async');
      expect(focus, isNonNegative);
      expect(
        pager.substring(focus, focus + 900),
        contains('_hasFocusedOnce = true;'),
      );
    });

    // Each of the three screens used to do this from its own initState. When
    // the page view moved into the pager, the profile feed lost it entirely
    // and opened on a video that never initialised.
    test('the pager focuses what it opened on', () {
      final initState = pager.indexOf('void initState()');
      expect(initState, isNonNegative);
      final body = pager.substring(
        initState,
        pager.indexOf('void didUpdateWidget', initState),
      );

      expect(body, contains('addPostFrameCallback'));
      expect(body, contains('unawaited(_focus(_currentIndex))'));
    });
  });

  group('a backgrounded feed gives back what it was holding', () {
    // Pausing was enough while a preloaded neighbour was a finished file
    // download: it held a decoder, and that was all. A preload now opens the
    // stream instead, and `playWhenReady` false does not stop ExoPlayer
    // filling its buffer -- so a feed left in the background kept pulling a
    // neighbour nobody had asked for off the user's mobile data.
    test('background releases the neighbours and keeps the visible one', () {
      final pager = _read('lib/widgets/video_feed_pager.dart');

      final lifecycle = pager.indexOf('void didChangeAppLifecycleState(');
      expect(lifecycle, isNonNegative);
      expect(
        pager.substring(lifecycle, lifecycle + 400),
        contains('_releaseNeighboursForBackground()'),
      );

      final release = pager.indexOf(
        'Future<void> _releaseNeighboursForBackground() async {',
      );
      expect(release, isNonNegative);
      final body = pager.substring(release, release + 700);

      expect(body, contains('_videoManager.pauseAll(widget.contextKey)'));
      expect(
        body,
        contains('_videoManager.releaseControllersExcept('),
        reason: 'a paused player still holds a decoder and still buffers',
      );
      // Resuming has to be instant, and the visible video is the one player
      // whose bytes are not wasted.
      expect(body, contains('videos[_currentIndex].videoUrl'));
      // On the end-of-feed page there is nothing to come back to.
      expect(body, contains(': null'));
    });

    // Two buttons open the upload flow. Only the one on the video itself gave
    // the feed's decoders back, and what follows needs them: the upload form
    // opens a preview player of its own, then an ffmpeg pass runs over the
    // clip, while a paused feed player still holds a decoder and still fills
    // its buffer.
    test('both doors to the upload flow hand the feed back', () {
      final player = _read('lib/widgets/smart_video_player.dart');
      final home = _read('lib/screens/home_screen.dart');

      final inPlayer = player.indexOf('Future<void> _openAddVideo(');
      expect(inPlayer, isNonNegative);
      expect(
        player.substring(inPlayer, inPlayer + 700),
        contains('_videoManager.releaseControllersExcept('),
      );

      final fromHome = home.indexOf('Future<void> _openAddVideo() async {');
      expect(fromHome, isNonNegative);
      final homeBody = home.substring(fromHome, fromHome + 1100);
      expect(homeBody, contains("videoManager.releaseControllersExcept('home'"));
      expect(
        homeBody,
        contains('videos[index].videoUrl'),
        reason: 'the video being watched is kept, so coming back is free',
      );
    });

    // The tile of a released neighbour is still mounted and still holds the
    // reference. dispose() leaves isInitialized true, so only the registry
    // can answer whether it is still ours to call into.
    test('a released player cannot be called into', () {
      final player = _read('lib/widgets/smart_video_player.dart');
      final valid = player.indexOf('bool _isControllerValid(');
      expect(valid, isNonNegative);
      expect(
        player.substring(valid, valid + 300),
        contains('_videoManager.isPlayerLive(_player)'),
      );
    });
  });

  group('a preload warms bytes, not a decoder', () {
    // adfoot-production, 2026-08-23 01:43:14 and 01:43:17:
    //   MediaCodecVideoRenderer error ... format_supported=YES
    // on `isPreload: true`, 1080p. The device could decode the format; every
    // instance was taken. A radius of 3 meant six extra hardware decoders
    // alive for videos nobody was watching.
    test('only the nearest neighbour gets a player', () {
      final scheduler = _read('lib/videos/domain/video_preload_scheduler.dart');
      final manager = _read('lib/videos/video_manager.dart');

      expect(scheduler, contains('required bool warmFileOnly'));
      expect(scheduler, contains('final warmFileOnly = position > 0;'));
      expect(manager, contains('Future<void> warmVideoFile(Video video)'));

      final callback = manager.indexOf('preload: (contextKey, video,');
      expect(callback, isNonNegative);
      final body = manager.substring(callback, callback + 420);
      expect(body, contains('if (warmFileOnly)'));
      expect(body, contains('return warmVideoFile(video);'));
    });

    // The ceiling has to sit where the hardware sits. Eight was chosen to
    // match the largest per-context budget, and the error came back anyway
    // with only the home feed open.
    test('the decoder budget is the hardware budget', () {
      expect(
        _read('lib/videos/video_manager.dart'),
        contains('static const int _globalMaxActive = 4;'),
      );
    });

    // Preloads used to queue on _maxConcurrentInits because they went through
    // initializeController. Warming the file instead — which is what stops
    // them opening decoders — took them out from under that gate too, and a
    // radius of 3 starts five whole-file downloads inside 700 ms against the
    // video being watched. The decoder budget was not the only budget the
    // preload path was spending.
    test('a warm still queues for the network', () {
      // The throttle moved next to the transfers it throttles: a warm is a
      // download that is dropped rather than queued when the connection is
      // busy, and VideoDownloadService already owns "a URL goes in, a file
      // comes out".
      final downloads = _read('lib/videos/data/video_download_service.dart');
      expect(downloads, contains('static const int maxConcurrentWarms = 2;'));

      final warm = downloads.indexOf('Future<void> warmFile(String url)');
      expect(warm, isNonNegative);
      final body = downloads.substring(warm, warm + 900);

      expect(body, contains('if (_activeWarms >= maxConcurrentWarms) return;'));
      expect(body, contains('_activeWarms++;'));
      expect(body, contains('_activeWarms--;'));
      expect(
        body,
        contains('finally'),
        reason: 'a failed warm must give its slot back',
      );

      // Claimed with no await between the check and the increment, or the
      // limit is only a suggestion.
      final check = body.indexOf('if (_activeWarms >= maxConcurrentWarms)');
      final claim = body.indexOf('_activeWarms++;');
      expect(
        body.substring(check, claim),
        isNot(contains('await')),
        reason: 'the slot must be claimed atomically',
      );

      // And the manager still picks which rendition gets warmed.
      final manager = _read('lib/videos/video_manager.dart');
      expect(manager, contains('_downloads.warmFile('));
      expect(manager, contains('VideoSourceSelector.preferredSource('));
    });
  });

  group('one owner per concern', () {
    late String pager;
    late String home;
    late String player;

    setUpAll(() {
      pager = _code('lib/widgets/video_feed_pager.dart');
      home = _code('lib/screens/home_screen.dart');
      player = _code('lib/widgets/smart_video_player.dart');
    });

    // `WakelockPlus` is one device-wide switch. Two owners each kept their
    // own cached boolean and could not see each other's writes: the player
    // disabling it on pause left the home screen still believing it was on,
    // so its next `_setWakelock(true)` short-circuited on
    // `_wakelockOn == enable` and re-enabled nothing. The screen could dim
    // in the middle of a video.
    //
    // The player is also the only one that can answer correctly: it is driven
    // by the controller's tick, where the screen sampled `isPlaying` once,
    // 50 ms after a focus.
    test('the wakelock has exactly one owner', () {
      expect(player, contains('WakelockPlus'));

      for (final entry in {'home': home, 'pager': pager}.entries) {
        expect(
          entry.value,
          isNot(contains('WakelockPlus')),
          reason: '${entry.key} must not drive the device switch',
        );
        expect(entry.value, isNot(contains('_setWakelock')));
      }
    });

    // Both observed the lifecycle, so backgrounding paused the feed twice
    // and resuming focused the current video twice.
    test('the feed lifecycle has exactly one observer', () {
      expect(pager, contains('with WidgetsBindingObserver'));
      expect(pager, contains('void didChangeAppLifecycleState('));
      expect(
        home,
        isNot(contains('void didChangeAppLifecycleState(')),
        reason: 'the pager pauses and re-focuses for every feed',
      );
      expect(home, isNot(contains('WidgetsBindingObserver')));
    });

    // Both were left behind by the extraction: a method that does nothing,
    // called twelve times, and a parameter nothing reads.
    test('nothing is left calling into emptiness', () {
      expect(home, isNot(contains('_refreshFocusVideos')));
      expect(player, isNot(contains('videoList')));
      expect(pager, isNot(contains('videoList: videos')));
    });

    // Three ways to load the same picture. `VideoController` warms video
    // stills into `DefaultCacheManager`; `CachedNetworkImage` reads that
    // store, and `Image.network` has no disk cache at all. The grids and the
    // search sheet used the one that could not see the prefetch, so they
    // re-downloaded every thumbnail on every scroll, and again after every
    // restart — on precisely the two surfaces the prefetch was added for.
    test('video thumbnails all read the store the prefetch fills', () {
      const surfaces = <String>[
        'lib/widgets/tiktok_video_player.dart',
        'lib/screens/profile_screen_widgets.dart',
        'lib/screens/home_screen_search_sheet.dart',
      ];

      for (final path in surfaces) {
        final source = _code(path);
        expect(source, contains('CachedNetworkImage('), reason: path);
        expect(
          source,
          isNot(contains('Image.network(')),
          reason: '$path must not bypass the disk cache',
        );
      }

      expect(
        _code('lib/controller/video_controller.dart'),
        contains('DefaultCacheManager().downloadFile(thumbUrl)'),
        reason: 'the store the widgets above read',
      );
    });
  });
}
