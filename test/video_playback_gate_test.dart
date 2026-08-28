import 'package:adfoot/videos/domain/video_lifecycle_observer.dart';
import 'package:adfoot/videos/video_manager.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two production symptoms, one gap.
///
/// The manager is what actually calls `play()` — `initializeController(
/// autoPlay: true)` does it in three places, from inside an await that can
/// outlive the reason it was started — and it asked nobody whether playback
/// was still wanted. So a video kept playing after the app was backgrounded,
/// and a video left while loading started playing once it finished.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoManager manager;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    manager = VideoManager();
    manager.resetPlaybackGateForTests();
  });

  tearDown(() => manager.resetPlaybackGateForTests());

  group('a context with no focus yet', () {
    // The first activation of a freshly opened feed has no previous page, and
    // must not be blocked by the absence of one.
    test('allows playback', () {
      expect(manager.canStartPlayback('home', 'https://a/1.mp4'), isTrue);
    });
  });

  group('focus decides which video may start', () {
    test('the focused video may play and the others may not', () async {
      await manager.pauseAllExcept('home', 'https://a/2.mp4');

      expect(manager.canStartPlayback('home', 'https://a/2.mp4'), isTrue);
      expect(
        manager.canStartPlayback('home', 'https://a/1.mp4'),
        isFalse,
        reason: 'the video the user scrolled away from must not start',
      );
    });

    // The reported bug: a slow load completes after the user has moved on.
    test('a load that lands after the user scrolled on is refused', () async {
      await manager.pauseAllExcept('home', 'https://a/1.mp4');
      expect(manager.canStartPlayback('home', 'https://a/1.mp4'), isTrue);

      // The user swipes; the orchestrator records the new focus while the
      // initialisation for the previous video is still in flight.
      await manager.pauseAllExcept('home', 'https://a/2.mp4');

      expect(
        manager.canStartPlayback('home', 'https://a/1.mp4'),
        isFalse,
        reason: 'this is the video that used to start playing by itself',
      );
    });

    test('contexts do not decide for each other', () async {
      await manager.pauseAllExcept('home', 'https://a/1.mp4');
      await manager.pauseAllExcept('profile:u1', 'https://a/9.mp4');

      expect(manager.canStartPlayback('home', 'https://a/1.mp4'), isTrue);
      expect(manager.canStartPlayback('profile:u1', 'https://a/9.mp4'), isTrue);
      expect(manager.canStartPlayback('home', 'https://a/9.mp4'), isFalse);
    });

    // Clearing focus is how a feed says "nothing here owns the screen".
    test('clearing focus reopens the gate', () async {
      await manager.pauseAllExcept('home', 'https://a/1.mp4');
      expect(manager.canStartPlayback('home', 'https://a/2.mp4'), isFalse);

      await manager.pauseAllExcept('home', null);
      expect(manager.canStartPlayback('home', 'https://a/2.mp4'), isTrue);
    });
  });

  group('the app in the background', () {
    test('refuses every video, focused or not', () async {
      await manager.pauseAllExcept('home', 'https://a/1.mp4');
      expect(manager.canStartPlayback('home', 'https://a/1.mp4'), isTrue);

      await manager.setAppResumed(false);

      expect(manager.isAppResumed, isFalse);
      expect(
        manager.canStartPlayback('home', 'https://a/1.mp4'),
        isFalse,
        reason: 'this is the video that kept playing in the background',
      );
    });

    test('returning to the foreground reopens the gate', () async {
      await manager.pauseAllExcept('home', 'https://a/1.mp4');
      await manager.setAppResumed(false);
      await manager.setAppResumed(true);

      expect(manager.isAppResumed, isTrue);
      expect(manager.canStartPlayback('home', 'https://a/1.mp4'), isTrue);
    });

    // Nothing is resumed by the manager: coming back is the widget's
    // decision, so only the video actually on screen restarts.
    test('focus survives a trip to the background', () async {
      await manager.pauseAllExcept('home', 'https://a/2.mp4');
      await manager.setAppResumed(false);
      await manager.setAppResumed(true);

      expect(manager.canStartPlayback('home', 'https://a/2.mp4'), isTrue);
      expect(manager.canStartPlayback('home', 'https://a/1.mp4'), isFalse);
    });
  });

  group('the lifecycle observer drives the gate', () {
    test('only resumed counts as the foreground', () async {
      final observer = VideoLifecycleObserver(videoManager: manager);

      for (final state in const <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        await manager.setAppResumed(true);
        observer.didChangeAppLifecycleState(state);
        await Future<void>.delayed(Duration.zero);
        expect(
          manager.isAppResumed,
          isFalse,
          reason: '$state has no surface to play to',
        );
      }

      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(manager.isAppResumed, isTrue);
    });

    test('starting twice registers one observer', () {
      final observer = VideoLifecycleObserver(videoManager: manager);
      observer.start();
      observer.start();
      observer.stop();
      // A second stop must not throw either.
      observer.stop();
    });
  });
}
