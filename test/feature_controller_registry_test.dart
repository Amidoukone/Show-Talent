import 'dart:io';

import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A video context is not just a controller: it owns a Firestore
/// subscription and every native player `VideoManager` holds under that key.
/// Tearing it down while a screen is still using it is silent — the feed
/// simply stops updating and its players disappear.
///
/// `ProfileController` has been reference-counted since the day that bug was
/// found for profiles. `VideoController` was not, even though
/// `ProfileScreen` and `ProfileVideoScrollView` hold the same
/// `profile:<uid>` context at the same time, each with its own ensure/release
/// pair.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const contextKey = 'profile:registry-test';

  VideoController ensure() {
    return FeatureControllerRegistry.ensureVideoController(
      contextKey: contextKey,
      enableLiveStream: false,
      enableFeedFetch: false,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FeatureControllerRegistry.resetVideoControllerRefCountsForTests();
    if (Get.isRegistered<VideoController>(tag: contextKey)) {
      Get.delete<VideoController>(tag: contextKey, force: true);
    }
  });

  tearDown(() {
    FeatureControllerRegistry.resetVideoControllerRefCountsForTests();
    if (Get.isRegistered<VideoController>(tag: contextKey)) {
      Get.delete<VideoController>(tag: contextKey, force: true);
    }
  });

  group('a video context survives until its last holder lets go', () {
    test('two holders share one controller', () {
      final first = ensure();
      final second = ensure();

      expect(identical(first, second), isTrue);
      expect(FeatureControllerRegistry.videoControllerRefCount(contextKey), 2);
    });

    // The case that was unguarded: the scroll view pops while the profile
    // screen underneath still holds the context.
    test('the first release keeps the controller alive', () {
      ensure();
      ensure();

      FeatureControllerRegistry.releaseVideoController(contextKey);

      expect(Get.isRegistered<VideoController>(tag: contextKey), isTrue);
      expect(FeatureControllerRegistry.videoControllerRefCount(contextKey), 1);
    });

    test('the last release tears it down', () {
      ensure();
      ensure();

      FeatureControllerRegistry.releaseVideoController(contextKey);
      FeatureControllerRegistry.releaseVideoController(contextKey);

      expect(Get.isRegistered<VideoController>(tag: contextKey), isFalse);
      expect(FeatureControllerRegistry.videoControllerRefCount(contextKey), 0);
    });

    // GetX refuses to delete a permanent instance without force: true, so an
    // unbalanced release must not leave the count in a state where the next
    // one under-counts.
    test('an extra release is harmless', () {
      ensure();

      FeatureControllerRegistry.releaseVideoController(contextKey);
      FeatureControllerRegistry.releaseVideoController(contextKey);

      expect(Get.isRegistered<VideoController>(tag: contextKey), isFalse);
      expect(FeatureControllerRegistry.videoControllerRefCount(contextKey), 0);
    });

    test('a fresh ensure after teardown builds a new controller', () {
      final first = ensure();
      FeatureControllerRegistry.releaseVideoController(contextKey);

      final second = ensure();

      expect(identical(first, second), isFalse);
      expect(Get.isRegistered<VideoController>(tag: contextKey), isTrue);
    });
  });

  group('one owner per context', () {
    String read(String path) => File(path).readAsStringSync();

    // The grid only renders images; every player under `profile:<uid>` is
    // created by ProfileVideoScrollView's orchestrator and destroyed by it.
    // A second teardown from the screen only obscured who owns the context.
    test('the profile screen claims and releases, but does not tear down', () {
      final profileScreen = read('lib/screens/profile_screen.dart');

      final tapHandler = profileScreen.substring(
        profileScreen.indexOf("final contextKey = 'profile:\${widget.uid}';"),
      );
      final release = tapHandler.indexOf(
        'FeatureControllerRegistry.releaseVideoController(',
      );
      expect(release, isNonNegative);

      expect(
        tapHandler.substring(0, release),
        isNot(contains('_videoManager.disposeAllForContext(')),
        reason: 'ProfileVideoScrollView has already done exactly this in its '
            'own dispose, and VideoController.onClose is the backstop',
      );
    });

    // The owner moved but the rule did not: whoever *creates* the players
    // destroys them. The scroll view now creates them by hosting a
    // VideoFeedPager, and the pager disposes its own orchestrator.
    test('the scroll view is the one that tears its players down', () {
      final scrollView = read('lib/screens/profil_video_scrollview.dart');
      final pager = read('lib/widgets/video_feed_pager.dart');

      expect(scrollView, contains('VideoFeedPager('));
      expect(
        scrollView,
        contains(
          'FeatureControllerRegistry.releaseVideoController(widget.contextKey);',
        ),
      );
      expect(pager, contains('unawaited(_orchestrator.onDispose());'));
      expect(
        pager,
        contains("unawaited(_videoManager.pauseAll(widget.contextKey));"),
      );
    });
  });

  group('the third copy of the video feed is gone', () {
    test('video_feed_screen.dart no longer exists', () {
      expect(
        File('lib/screens/video_feed_screen.dart').existsSync(),
        isFalse,
        reason: 'it was never referenced by any screen, and had drifted away '
            'from the two feeds that are actually reachable',
      );
    });

    // Deliberately narrower than "the string appears anywhere": several files
    // now carry a comment explaining what was removed and why, and that
    // history is worth keeping. What must not survive is anything that would
    // actually resolve — the class identifier, an import, or a path literal a
    // guardrail would try to read.
    test('nothing resolves to it any more', () {
      final offenders = <String>[];
      final live = <RegExp>[
        RegExp(r'\bVideoFeedScreen\b'),
        RegExp(r'''import\s+['"][^'"]*video_feed_screen\.dart['"]'''),
        RegExp(r'''['"]lib/screens/video_feed_screen\.dart['"]'''),
      ];

      for (final directory in ['lib', 'test', 'scripts']) {
        for (final entity in Directory(directory).listSync(recursive: true)) {
          if (entity is! File) continue;
          final path = entity.path.replaceAll('\\', '/');
          if (!path.endsWith('.dart') && !path.endsWith('.ps1')) continue;
          if (path.endsWith('feature_controller_registry_test.dart')) continue;

          final content = entity.readAsStringSync();
          for (final pattern in live) {
            if (pattern.hasMatch(content)) {
              offenders.add('$path: ${pattern.pattern}');
            }
          }
        }
      }

      expect(offenders, isEmpty);
    });
  });
}
