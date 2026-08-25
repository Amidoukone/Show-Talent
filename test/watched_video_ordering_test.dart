import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/videos/data/watched_video_store.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The feed's job here is not to never end. It is to never repeat itself
/// while anything is still unseen.
///
/// adfoot-production held 14 ready videos on 2026-08-24, published by three
/// accounts, with a cap of 10 per player. A feed ordered by publication date
/// alone therefore opens on the same clip every session until somebody
/// uploads, which is the opposite of what a recruiter opens the app for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    SharedPreferences.setMockInitialValues({});
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'test-api-key',
          appId: '1:1234567890:android:test',
          messagingSenderId: '1234567890',
          projectId: 'test-project',
          storageBucket: 'test-project.appspot.com',
        ),
      );
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
  });

  tearDown(() => WatchedVideoStore.instance.resetForTests());

  Video buildVideo(String id) {
    return Video(
      id: id,
      videoUrl: 'https://cdn.example.com/$id.mp4',
      thumbnailUrl: '',
      description: 'desc $id',
      caption: 'caption $id',
      profilePhoto: '',
      uid: 'user-$id',
    );
  }

  VideoController homeController() => VideoController(
    contextKey: 'home',
    enableLiveStream: true,
    enableFeedFetch: true,
  );

  group('what counts as watched', () {
    test('a video that never rendered is never watched', () {
      expect(
        WatchedVideoPolicy.countsAsWatched(
          hadFirstFrame: false,
          maxPosition: const Duration(seconds: 30),
          completionRate: 1.0,
        ),
        isFalse,
        reason: 'nothing was on screen, whatever the clock says',
      );
    });

    // A fast scroll puts every video on screen for a moment. Counting that as
    // watched would empty the unseen set in one pass, which is the state this
    // ordering exists to avoid.
    test('a glance is not a watch', () {
      expect(
        WatchedVideoPolicy.countsAsWatched(
          hadFirstFrame: true,
          maxPosition: const Duration(milliseconds: 900),
          completionRate: 0.05,
        ),
        isFalse,
      );
    });

    // Two thresholds because the clips run from 9 s to 160 s: three seconds
    // means nothing on the long ones, half a clip is unreachable on them.
    test('three seconds is enough on a long clip', () {
      expect(
        WatchedVideoPolicy.countsAsWatched(
          hadFirstFrame: true,
          maxPosition: const Duration(seconds: 4),
          completionRate: 0.02,
        ),
        isTrue,
      );
    });

    test('half a clip is enough on a short one', () {
      expect(
        WatchedVideoPolicy.countsAsWatched(
          hadFirstFrame: true,
          maxPosition: const Duration(milliseconds: 1500),
          completionRate: 0.6,
        ),
        isTrue,
      );
    });
  });

  group('the store remembers what was watched', () {
    test('a watch survives a reload', () async {
      SharedPreferences.setMockInitialValues({});
      WatchedVideoStore.instance.resetForTests();

      await WatchedVideoStore.instance.markWatched('v1');

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(WatchedVideoStore.storageKey);
      expect(raw, isNotNull);
      expect(raw, contains('v1'));
    });

    test('the oldest watches are evicted, never the newest', () async {
      final seeded = <String, int>{
        for (var i = 0; i < WatchedVideoStore.maxEntries; i++) 'old-$i': i + 1,
      };
      WatchedVideoStore.instance.resetForTests(
        watchedAtMsById: seeded,
        now: () => DateTime.fromMillisecondsSinceEpoch(99999999),
      );

      await WatchedVideoStore.instance.markWatched('brand-new');

      expect(
        WatchedVideoStore.instance.entryCount,
        WatchedVideoStore.maxEntries,
      );
      expect(WatchedVideoStore.instance.hasWatched('brand-new'), isTrue);
      expect(
        WatchedVideoStore.instance.hasWatched('old-0'),
        isFalse,
        reason: 'the oldest watch is the one that goes',
      );
    });
  });

  group('the feed opens on what has not been seen', () {
    test('unwatched videos come first, in server order', () {
      WatchedVideoStore.instance.resetForTests(
        watchedAtMsById: const {'v1': 100, 'v2': 300},
      );
      final controller = homeController();

      controller.applyLiveWindowForTests([
        buildVideo('v1'),
        buildVideo('v2'),
        buildVideo('v3'),
        buildVideo('v4'),
      ]);

      expect(controller.videoList.map((v) => v.id).toList(), [
        'v3',
        'v4',
        'v1',
        'v2',
      ]);
    });

    // Least-recently-seen first: coming back after everything has been
    // watched should still not open on the clip just finished.
    test('already-watched videos return oldest-watch first', () {
      WatchedVideoStore.instance.resetForTests(
        watchedAtMsById: const {'v1': 900, 'v2': 100, 'v3': 500},
      );
      final controller = homeController();

      controller.applyLiveWindowForTests([
        buildVideo('v1'),
        buildVideo('v2'),
        buildVideo('v3'),
      ]);

      expect(controller.videoList.map((v) => v.id).toList(), [
        'v2',
        'v3',
        'v1',
      ]);
    });

    test('a feed with nothing watched keeps the server order untouched', () {
      WatchedVideoStore.instance.resetForTests();
      final controller = homeController();

      controller.applyLiveWindowForTests([
        buildVideo('v1'),
        buildVideo('v2'),
        buildVideo('v3'),
      ]);

      expect(controller.videoList.map((v) => v.id).toList(), [
        'v1',
        'v2',
        'v3',
      ]);
    });

    // Appending a page to the end is why the ordering stopped short of being
    // useful: the unseen videos of page two landed below the watched tail of
    // page one, so reaching them meant scrolling through everything already
    // seen. The part of the feed the user has not reached is re-ordered; the
    // part they have is frozen.
    test('a new page is merged below the current index, unseen first', () {
      WatchedVideoStore.instance.resetForTests(
        watchedAtMsById: const {'v2': 100, 'v3': 200, 'v4': 300},
      );
      final controller = homeController();

      controller.replaceVideos([
        buildVideo('v1'),
        buildVideo('v2'),
        buildVideo('v3'),
        buildVideo('v4'),
      ], selectedIndex: 1);

      // Page two arrives: one watched, one not.
      final merged = controller.appendBelowCurrentForTests([
        buildVideo('v5'),
        buildVideo('v6'),
      ]);

      expect(
        merged.take(2).map((v) => v.id).toList(),
        ['v1', 'v2'],
        reason: 'the current index and everything above it never moves',
      );
      expect(
        merged.skip(2).map((v) => v.id).toList(),
        ['v5', 'v6', 'v3', 'v4'],
        reason: 'below it, unseen first then oldest-watch first',
      );
    });

    // Pagination driven by distance to the end fetches the page holding the
    // unseen videos only after the user has scrolled through the watched
    // ones, which nobody does.
    test('the feed counts what is unseen ahead, not what is left', () {
      WatchedVideoStore.instance.resetForTests(
        watchedAtMsById: const {'v2': 100, 'v3': 200},
      );
      final controller = homeController();

      controller.replaceVideos([
        buildVideo('v1'),
        buildVideo('v2'),
        buildVideo('v3'),
        buildVideo('v4'),
      ]);

      expect(controller.unwatchedAfter(0), 1, reason: 'only v4 is unseen');
      expect(controller.unwatchedAfter(3), 0);
    });

    // A profile's videos are that player's filmography, not a discovery feed:
    // reordering them by what the viewer happened to watch would be wrong.
    test('a scoped feed is never reordered', () {
      WatchedVideoStore.instance.resetForTests(
        watchedAtMsById: const {'v1': 100},
      );
      final controller = VideoController(
        contextKey: 'profile:user-1',
        enableLiveStream: false,
        enableFeedFetch: false,
      );

      controller.replaceVideos([buildVideo('v1'), buildVideo('v2')]);

      expect(controller.videoList.map((v) => v.id).toList(), ['v1', 'v2']);
    });
  });
}
