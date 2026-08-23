import 'dart:io';

import 'package:adfoot/models/video.dart';
import 'package:adfoot/videos/domain/video_focus_orchestrator.dart';
import 'package:adfoot/videos/video_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guardrails for the video stabilization pass on 1.0.7+21, each one anchored
/// to something adfoot-production actually recorded rather than to something
/// that looked wrong in the source.
String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tearing down controllers does not crash the app', () {
    late String manager;

    setUpAll(() {
      manager = _read('lib/videos/video_manager.dart');
    });

    // client_logs, adfoot-production, 2026-08-22 at 08:01:20 and again at
    // 08:33:42:
    //   Concurrent modification during iteration: _Map len:4.
    //   #1 VideoManager.pauseAll (video_manager.dart:1605)
    // The loop held a live view of the LRU across an await while four other
    // code paths were free to write to it. Because the call site does not
    // await the result, the throw escapes into runZonedGuarded, and
    // AppBootstrap.reportZoneError books it in Crashlytics as fatal.
    test('pauseAll iterates a snapshot, not the live map', () {
      final start = manager.indexOf('Future<void> pauseAll(String contextKey)');
      expect(start, isNonNegative);
      final body = manager.substring(start, manager.indexOf('\n  }', start));

      expect(body, contains('.values.toList(growable: false)'));
      expect(
        body,
        isNot(contains('for (final player in lru.values)')),
        reason: 'this exact line is the one production crashed on',
      );
    });

    test('disposeAllForContext iterates a snapshot too', () {
      final start = manager.indexOf(
        'Future<void> disposeAllForContext(String contextKey)',
      );
      expect(start, isNonNegative);
      final body = manager.substring(start, start + 1400);

      expect(body, contains('lru.values.toList(growable: false)'));
      expect(
        body,
        isNot(contains('for (final player in lru.values)')),
        reason: 'an in-flight attempt() still removes from this same map when '
            'it fails, even after the context has been detached',
      );
    });

    test('the pauses on the page-change path run together', () {
      expect(manager, contains('await Future.wait(players.map(safePause));'));

      final start = manager.indexOf(
        'Future<void> pauseAllExcept(String contextKey, String? keepUrl)',
      );
      expect(start, isNonNegative);
      final body = manager.substring(start, manager.indexOf('\n  }', start));
      expect(body, contains('pauses.add(safePause(entry.value));'));
      expect(body, contains('await Future.wait(pauses);'));
    });

    test('pauseAll on a context that never existed is a no-op', () async {
      SharedPreferences.setMockInitialValues({});
      final videoManager = VideoManager();

      await expectLater(
        videoManager.pauseAll('context-that-was-never-created'),
        completes,
      );
    });
  });

  group('decoders are handed back before a second video surface opens', () {
    late String manager;
    late String player;

    setUpAll(() {
      manager = _read('lib/videos/video_manager.dart');
      player = _read('lib/widgets/smart_video_player.dart');
    });

    // Contexts each get their own _maxActive budget and none of them is torn
    // down when a route is pushed on top, so `home` and `profile:<uid>` hold
    // their controllers at the same time. The device's decoder pool is
    // neither per-context nor per-app. Pausing does not release a MediaCodec
    // instance; only disposing does.
    test('the manager can trim a context down to the video on screen', () {
      expect(
        manager,
        contains('Future<void> releaseControllersExcept('),
      );

      final start = manager.indexOf('Future<void> releaseControllersExcept(');
      final body = manager.substring(start, start + 1600);
      expect(body, contains('await safeDispose(player);'));
      expect(body, contains('_markStreaming(contextKey, key, isStreaming: false);'));
      expect(
        body,
        contains('.where((key) => key != resolvedKeep)'),
        reason: 'the video being watched must survive, or coming back to the '
            'feed is a cold start',
      );
    });

    test('the feed trims itself on its way to a profile', () {
      final start = player.indexOf('Future<void> _openPublisherProfile(');
      expect(start, isNonNegative);
      final body = player.substring(start, player.indexOf('\n  }', start));

      expect(body, contains('_videoManager.releaseControllersExcept('));
      expect(
        body.indexOf('_videoManager.releaseControllersExcept('),
        lessThan(body.indexOf('Get.to(')),
        reason: 'the point is to free them before the second surface asks',
      );
    });

    test('and on its way to the upload flow', () {
      final start = player.indexOf('Future<void> _openAddVideo(');
      expect(start, isNonNegative);
      final body = player.substring(start, player.indexOf('\n  }', start));

      expect(body, contains('_videoManager.releaseControllersExcept('));
    });

    test('trimming an unknown context is a no-op', () async {
      SharedPreferences.setMockInitialValues({});
      final videoManager = VideoManager();

      await expectLater(
        videoManager.releaseControllersExcept('never-created', 'whatever'),
        completes,
      );
    });

    // `releaseControllersExcept` patches the two transitions we knew about.
    // The budget is the structural version: `_maxActive` is per context, and
    // the device's decoder pool is not.
    test('the budget is app-wide, not per context', () {
      // Four, not the eight this test first pinned. Eight was chosen to
      // match the largest per-context budget so a single feed would never be
      // constrained -- and on 2026-08-23 the same MediaCodec error came back
      // on a *preload*, with the budget in place and only the home feed open.
      // The ceiling belongs where the hardware is, not where the software
      // would prefer it.
      expect(manager, contains('static const int _globalMaxActive = 4;'));
      expect(manager, contains('int get _totalActiveControllers =>'));
      expect(manager, contains('await _enforceGlobalLimit(contextKey,'));

      final start = manager.indexOf('Future<void> _enforceGlobalLimit(');
      expect(start, isNonNegative);
      final body = manager.substring(start, start + 1500);

      // The feed nobody is looking at gives its decoders back first; the
      // video on screen is never the one evicted.
      expect(
        body,
        contains('..._lruByContext.keys.where((key) => key != focusedContextKey)'),
      );
      expect(body, contains('!(isFocused && key == keepResolvedUrl)'));
      expect(
        body,
        contains('if (!await _releaseController(contextKey, oldestKey)) break;'),
        reason: 'a release that frees nothing must not loop',
      );
    });

    test('enforcing the limit on an empty manager is a no-op', () async {
      SharedPreferences.setMockInitialValues({});
      final videoManager = VideoManager();

      await expectLater(
        videoManager.enforceLimitForTests('nothing-here'),
        completes,
      );
    });
  });

  group('VideoManager is not a widget', () {
    test('it lives with the rest of the video code', () {
      expect(File('lib/videos/video_manager.dart').existsSync(), isTrue);
      expect(File('lib/widgets/video_manager.dart').existsSync(), isFalse);
    });

    // 1 923 lines holding the controller cache, the initialisation pipeline,
    // the downloads, the cache-size policing, the preload scheduling, the
    // bandwidth arbitration, the network profile, the UI notifications and
    // the metrics. The three with a clean boundary now have their own names.
    test('the collaborators with a boundary have been given one', () {
      const extracted = <String>[
        'lib/videos/data/video_download_service.dart',
        'lib/videos/domain/playback_bandwidth_arbiter.dart',
        'lib/videos/domain/video_preload_scheduler.dart',
      ];

      for (final path in extracted) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }

      final source = _read('lib/videos/video_manager.dart');
      expect(source, contains('final VideoDownloadService _downloads'));
      expect(source, contains('final PlaybackBandwidthArbiter _bandwidth'));
      expect(source, contains('late final VideoPreloadScheduler _preloads'));
    });

    // The scheduler resumes a preload after a delay, by which time the app
    // may have moved to another feed entirely. Reading the context from
    // shared state at that point would preload into whichever feed happened
    // to be current.
    test('a deferred preload carries the context it was scheduled with', () {
      final scheduler = _read('lib/videos/domain/video_preload_scheduler.dart');

      expect(scheduler, contains('String contextKey,'));
      expect(scheduler, contains('required bool warmFileOnly,'));
      expect(
        scheduler,
        contains('await preload('),
        reason: 'the context must travel with the call, not be read from '
            'shared state after the delay',
      );
      final call = scheduler.indexOf('await preload(');
      expect(
        scheduler.substring(call, call + 160),
        contains('contextKey,'),
      );
    });
  });

  group('a fling does not start a player per page it crosses', () {
    // A vertical PageView reports every page a fling passes over. Each report
    // reached initializeController, so six pages flicked past meant six
    // network streams and six native players opened for videos nobody would
    // watch. The request token discarded their results; it never stopped them
    // being started. adfoot-production shows what a device does when it runs
    // out of decoders under that pressure: on 2026-08-22 at 09:19,
    //   MediaCodecVideoRenderer error ... format_supported=YES
    // on a 1920x1080 AVC stream the device could decode perfectly well.
    VideoFocusOrchestrator orchestrator({Duration? settleDelay}) {
      SharedPreferences.setMockInitialValues({});
      return VideoFocusOrchestrator(
        contextKey: 'settle-test',
        videoManager: VideoManager(),
        videos: const <Video>[],
        settleDelay: settleDelay ?? const Duration(milliseconds: 120),
      );
    }

    final t0 = DateTime.utc(2026, 8, 22, 12);

    test('the first focus of a feed never waits', () {
      expect(
        orchestrator().shouldWaitForScrollToSettle(
          previousRequestAt: null,
          requestedAt: t0,
        ),
        isFalse,
        reason: 'cold start must not pay for a debounce nobody triggered',
      );
    });

    test('a page report on the heels of another one waits', () {
      expect(
        orchestrator().shouldWaitForScrollToSettle(
          previousRequestAt: t0,
          requestedAt: t0.add(const Duration(milliseconds: 30)),
        ),
        isTrue,
      );
    });

    test('a deliberate swipe does not wait', () {
      expect(
        orchestrator().shouldWaitForScrollToSettle(
          previousRequestAt: t0,
          requestedAt: t0.add(const Duration(milliseconds: 400)),
        ),
        isFalse,
      );
    });

    test('the window can be switched off entirely', () {
      expect(
        orchestrator(settleDelay: Duration.zero).shouldWaitForScrollToSettle(
          previousRequestAt: t0,
          requestedAt: t0.add(const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
    });

    test('the wait is followed by a staleness check, not by work', () {
      final source = _read('lib/videos/domain/video_focus_orchestrator.dart');
      final start = source.indexOf('await Future<void>.delayed(settleDelay);');
      expect(start, isNonNegative);

      final tail = source.substring(start, start + 260);
      expect(tail, contains('if (_isStale(localToken)) return null;'));
      expect(
        tail,
        contains('if (index >= _videos.length) return null;'),
        reason: 'the feed can shrink while we wait',
      );
    });
  });

  group('time-to-first-frame measures the wait the user actually has', () {
    // Every one of the 63 playback sessions logged in adfoot-production in
    // the fourteen days to 2026-08-22 reported timeToFirstFrameMs: 0 --
    // including sessions that went on to rebuffer for twenty seconds. The
    // tracker was created one line before play(), by which point
    // VideoFocusOrchestrator had already initialised and started the
    // controller, so the first frame was usually already on screen and got
    // stamped immediately.
    test('the session starts when the tile becomes active', () {
      final player = _read('lib/widgets/smart_video_player.dart');

      final start = player.indexOf('void _scheduleMaybePlay() {');
      expect(start, isNonNegative);
      final body = player.substring(start, player.indexOf('\n  }', start));

      expect(body, contains('_ensurePlaybackSession();'));
      expect(body, contains('if (_isActuallyVisible())'));
      expect(
        body.indexOf('_ensurePlaybackSession();'),
        lessThan(body.indexOf('_playDebounceTimer = Timer(')),
        reason: 'the clock has to start before the debounce, not after the '
            'controller is already playing',
      );
    });
  });

  group('the controls describe the controller they are attached to', () {
    // Playback speed lives on the native player, so a replacement controller
    // always starts at 1x. This widget's state did not, and every path that
    // swaps the controller does it silently: automatic recovery, manual
    // retry, an adaptive quality change, or the manager simply handing over
    // the controller it finished initialising.
    test('a new controller resets the speed badge and any drag', () {
      final source = _read('lib/widgets/tiktok_video_player.dart');

      final start = source.indexOf('void didUpdateWidget(');
      expect(start, isNonNegative);
      final body = source.substring(start, source.indexOf('\n  }', start));

      expect(
        body,
        contains('if (identical(oldWidget.controller, widget.controller)) '
            'return;'),
      );
      expect(body, contains('_playbackSpeed = 1.0;'));
      expect(body, contains('_isDragging = false;'));
    });
  });

  group('a stream shares the connection sooner', () {
    test('the stability window is three watchdog ticks', () {
      final player = _read('lib/widgets/smart_video_player.dart');

      expect(
        player,
        contains('static const int _smoothTicksBeforeStable = 3;'),
        reason: 'a slow link is now classified as one and preloads nothing, '
            'so this window no longer stands in for the bandwidth measurement',
      );
    });
  });
}
