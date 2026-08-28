import 'dart:io';

import 'package:adfoot/videos/domain/network_profile.dart';
import 'package:adfoot/videos/domain/video_network_tuning.dart';
import 'package:adfoot/videos/domain/video_playback_metrics.dart';
import 'package:adfoot/videos/domain/video_ui_signals.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `VideoManager` was 1 923 lines holding eight unrelated jobs at once: the
/// controller cache, the initialisation pipeline, the downloads, the
/// cache-size policing, the preload scheduling, the bandwidth arbitration, the
/// network profile, the UI notifications and the metrics.
///
/// Nothing in it could be tested without constructing all of it, so almost
/// none of it was — which is how a throughput calculation that was wrong by a
/// factor of a thousand survived long enough to reach production.
String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the UI state of a video is one thing', () {
    late VideoUiSignals signals;

    setUp(() => signals = VideoUiSignals());

    test('a load state reaches the video that changed, and only it', () {
      final watched = signals.watch('home', 'a.mp4');
      final other = signals.watch('home', 'b.mp4');
      final watchedBefore = watched.value;
      final otherBefore = other.value;

      signals.setLoadState('home', 'a.mp4', VideoLoadState.ready);

      expect(watched.value, greaterThan(watchedBefore));
      expect(other.value, otherBefore);
      expect(signals.loadState('home', 'a.mp4'), VideoLoadState.ready);
    });

    test('an unresolved url resolves to itself', () {
      expect(signals.resolveKey('home', 'a.mp4'), 'a.mp4');
      expect(signals.resolvedUrl('home', 'a.mp4'), isNull);

      signals.setResolvedUrl('home', 'a.mp4', 'a_480p.mp4');

      expect(signals.resolveKey('home', 'a.mp4'), 'a_480p.mp4');
      expect(signals.originalUrlsFor('home', 'a_480p.mp4'), ['a.mp4']);
    });

    // Dropping a context's state without waking its watchers left a widget
    // rendering what it knew before the teardown, until something unrelated
    // happened to rebuild it.
    test('tearing down a context wakes everyone still watching it', () {
      final watched = signals.watch('home', 'a.mp4');
      signals.setLoadState('home', 'a.mp4', VideoLoadState.ready);
      final before = watched.value;

      signals.forgetContext('home');

      expect(watched.value, greaterThan(before));
      expect(signals.loadState('home', 'a.mp4'), isNull);
    });

    // The notifiers belong to the widgets, not to the context: two tiles can
    // watch the same video, and the first to leave must not silence the
    // second.
    test('a notifier survives until its last watcher lets go', () {
      final first = signals.watch('home', 'a.mp4');
      final second = signals.watch('home', 'a.mp4');
      expect(identical(first, second), isTrue);

      signals.unwatch('home', 'a.mp4');
      final before = second.value;
      signals.setLoadState('home', 'a.mp4', VideoLoadState.ready);

      expect(second.value, greaterThan(before));
    });
  });

  group('the tier decides what playback may cost', () {
    // Every tier's settings, in one table, reachable without building the
    // controller cache.
    test('a slower tier asks for less of everything', () {
      // The detector reads a cached profile from SharedPreferences on
      // construction; the tuning table itself needs nothing.
      SharedPreferences.setMockInitialValues({});
      final controller = VideoNetworkTuningController();

      controller.override(
        const NetworkProfile(tier: NetworkProfileTier.high),
      );
      final high = controller.tuning;

      controller.override(
        const NetworkProfile(tier: NetworkProfileTier.medium),
      );
      final medium = controller.tuning;

      controller.override(const NetworkProfile(tier: NetworkProfileTier.low));
      final low = controller.tuning;

      expect(high.maxActive, greaterThan(medium.maxActive));
      expect(medium.maxActive, greaterThan(low.maxActive));
      expect(high.preloadRadius, greaterThan(medium.preloadRadius));
      expect(
        low.preloadRadius,
        0,
        reason: 'a link this slow must not compete with itself',
      );
      expect(
        low.activeTimeout,
        greaterThan(high.activeTimeout),
        reason: 'a slow link needs longer before it is called a failure',
      );
      expect(controller.isHighBandwidth, isFalse);
    });

    // The first videos of a session are requested before any measurement
    // exists. Assuming `high` there would ask for the heaviest rendition on
    // no evidence at all.
    test('the bootstrap assumption is medium, never high', () {
      expect(
        VideoNetworkTuningController.bootstrapProfile.tier,
        NetworkProfileTier.medium,
      );
    });
  });

  group('metrics count without owning the players', () {
    VideoMetricEvent event(VideoMetricType type, {bool usedCache = false}) {
      return VideoMetricEvent(
        type: type,
        url: 'https://example.test/a.mp4',
        isPreload: false,
        usedCache: usedCache,
      );
    }

    test('the cache-hit rate is the rate of what actually hit', () {
      final recorder = VideoPlaybackMetricsRecorder();

      recorder.record(event(VideoMetricType.initSuccess, usedCache: true));
      recorder.record(event(VideoMetricType.initSuccess));

      expect(recorder.initCount, 2);
      expect(recorder.cacheHits, 1);
      expect(recorder.cacheHitRate, 0.5);
    });

    test('an error counts as an error, not as an initialisation', () {
      final recorder = VideoPlaybackMetricsRecorder();

      recorder.record(event(VideoMetricType.initError));

      expect(recorder.errorCount, 1);
      expect(recorder.initCount, 0);
      expect(recorder.cacheHitRate, 0.0);
    });

    test('the listener receives the running totals, not a bare event', () {
      final recorder = VideoPlaybackMetricsRecorder();
      VideoMetricEvent? seen;
      recorder.onMetrics = (e) => seen = e;

      recorder.record(event(VideoMetricType.initSuccess, usedCache: true));

      expect(seen?.initCount, 1);
      expect(seen?.cacheHits, 1);
      expect(seen?.cacheHitRate, 1.0);
    });
  });

  group('every job has a file, and the file says which job', () {
    test('the collaborators exist and the manager delegates to each', () {
      const collaborators = <String, String>{
        'lib/videos/data/video_download_service.dart': '_downloads',
        'lib/videos/domain/playback_bandwidth_arbiter.dart': '_bandwidth',
        'lib/videos/domain/video_preload_scheduler.dart': '_preloads',
        'lib/videos/domain/video_ui_signals.dart': '_ui',
        'lib/videos/domain/video_network_tuning.dart': '_network',
        'lib/videos/domain/video_playback_metrics.dart': '_metrics',
        'lib/videos/domain/player_lifetime_registry.dart': '_lifetimes',
        'lib/videos/domain/playback_gate.dart': '_gate',
      };

      final manager = _read('lib/videos/video_manager.dart');
      collaborators.forEach((path, field) {
        expect(File(path).existsSync(), isTrue, reason: path);
        expect(manager, contains('$field.'), reason: '$path is unused');
      });
    });

    // What is left is one job: hand back a ready controller for this URL in
    // this context, and keep the cache within budget. It is still large, and
    // saying so out loud is the point of this number — it must not creep back.
    // Re-baselined from 1450 when the playback gate was added, and the bound
    // did its job: the gate first went in as fields and methods on the
    // manager, this test refused it, and it became the ninth collaborator
    // above instead. What is left here is delegation -- five one-liners, the
    // pause that backgrounding needs, and three call sites asking the gate
    // whether playback may start -- which costs 34 lines.
    //
    // The collaborator assertion above is the stronger guarantee; this number
    // only stops that delegation growing back into an implementation.
    test('the manager keeps only the controller cache and its pipeline', () {
      final lines = _read('lib/videos/video_manager.dart').split('\n').length;

      expect(
        lines,
        lessThan(1500),
        reason: 'it was 1923 across nine jobs; anything moving back in is a '
            'new job arriving in the wrong place',
      );
    });
  });
}
