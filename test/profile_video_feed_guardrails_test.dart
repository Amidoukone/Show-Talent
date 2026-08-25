import 'dart:io';

import 'package:adfoot/controller/video_controller.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _read(String path) => File(path).readAsStringSync();

/// A profile's videos are the same pipeline as the home feed, driven by a
/// different list. The two defects below both come from that: the surface
/// holds one list, `ProfileController` holds another, and nothing kept them
/// agreeing.
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

  late String scrollView;
  late String profileController;

  setUpAll(() {
    scrollView = _read('lib/screens/profil_video_scrollview.dart');
    profileController = _read('lib/controller/profile_controller.dart');
  });

  group('paginating a profile does not move the user', () {
    // ProfileController keeps its list to 25 entries and drops the excess
    // from the *front* (_videoMemoryLimit), while a page brings 20. So the
    // fetch that adds twenty removes fifteen, every index into the old list
    // is off by fifteen, and handing the old index back moved the user
    // fifteen videos forward from the one they were watching.
    test('the position is anchored to the video, not to its index', () {
      expect(profileController, contains('static const int _videoFetchLimit = 20;'));
      expect(profileController, contains('static const int _videoMemoryLimit = 25;'));
      expect(
        profileController,
        contains('videoList.removeRange(0, toRemove);'),
        reason: 'the window slides from the front, which is what shifts indices',
      );

      final load = scrollView.indexOf('Future<void> _loadMoreProfileVideos() async {');
      expect(load, isNonNegative);
      final body = scrollView.substring(load, scrollView.indexOf('\n  }', load));

      expect(body, contains('final anchorId = before.isEmpty ? null : before[anchorIndex].id;'));
      expect(body, contains('playable.indexWhere((video) => video.id == anchorId)'));
      expect(
        body,
        isNot(contains('selectedIndex: _pager.currentIndex)')),
        reason: 'an index into the old list means nothing after a slide',
      );
    });

    // replaceVideos writes currentIndex; it does not move the page view. Left
    // behind, the pager shows one video while every tile believes a different
    // one is active, so nothing plays at all.
    test('the page view follows the index it was given', () {
      final load = scrollView.indexOf('Future<void> _loadMoreProfileVideos() async {');
      final body = scrollView.substring(load, scrollView.indexOf('\n  }', load));

      expect(body, contains('_vc.replaceVideos(playable, selectedIndex: nextIndex);'));
      expect(body, contains('_pager.jumpToPage(nextIndex);'));
      expect(body, contains('await _pager.activate(nextIndex);'));
      expect(
        body,
        contains('if (nextIndex == anchorIndex) return;'),
        reason: 'a list that did not slide must not be re-focused for nothing',
      );
    });
  });

  group('a deleted video leaves every list that held it', () {
    test('the controller reports what it deleted', () {
      final controller = VideoController(
        contextKey: 'profile:user-1',
        enableLiveStream: false,
        enableFeedFetch: false,
      );

      expect(controller.deletedVideoIds, isEmpty);
      expect(
        () => controller.deletedVideoIds.add('x'),
        throwsUnsupportedError,
        reason: 'callers reconcile with it, they do not write to it',
      );
    });

    test('the profile can drop what no longer exists', () {
      expect(
        profileController,
        contains('void removeVideosLocally(Iterable<String> videoIds)'),
      );
      expect(profileController, contains('videoList.removeWhere((video) => ids.contains(video.id));'));
      expect(
        profileController,
        contains('update();'),
        reason: 'the grid is a GetBuilder surface and has to be told',
      );
    });

    // Two symptoms, one cause. Pagination handed the deleted document back to
    // the player with a URL that no longer resolves; the grid went on showing
    // it after the user came back.
    test('both the pagination and the exit reconcile', () {
      final load = scrollView.indexOf('Future<void> _loadMoreProfileVideos() async {');
      final loadBody = scrollView.substring(load, scrollView.indexOf('\n  }', load));
      expect(
        loadBody,
        contains('profileController.removeVideosLocally(_vc.deletedVideoIds);'),
      );

      final exit = scrollView.indexOf('Future<void> _safeExit() async {');
      expect(exit, isNonNegative);
      final exitBody = scrollView.substring(exit, scrollView.indexOf('\n  }', exit));
      expect(exitBody, contains('removeVideosLocally(_vc.deletedVideoIds)'));
      expect(
        exitBody,
        contains('Get.isRegistered<ProfileController>(tag: widget.uid)'),
        reason: 'the profile may already be gone by the time we leave',
      );
    });
  });

  group('the profile feed keeps the pipeline and not the feed policy', () {
    // The whole playback pipeline is shared, so every fix to it lands here
    // too: the streamed preload, the two-stage bandwidth release, the active
    // init claim, the background release.
    test('it drives the same pager', () {
      expect(scrollView, contains('VideoFeedPager('));
      expect(scrollView, contains('contextKey: widget.contextKey,'));
    });

    // But the policies that belong to a discovery feed do not: a filmography
    // is chronological, and "you are up to date, come back later" is the
    // wrong thing to say about one player's videos.
    test('it takes neither the unseen-first order nor the end card', () {
      expect(scrollView, contains('enableFeedFetch: false,'));
      expect(
        scrollView,
        isNot(contains('endOfFeedBuilder')),
        reason: 'a profile is not a fil the user runs to the end of',
      );

      final controller = _read('lib/controller/video_controller.dart');
      final order = controller.indexOf('List<Video> _watchedAwareOrder(');
      expect(order, isNonNegative);
      expect(
        controller.substring(order, order + 260),
        contains('if (!enableFeedFetch || videos.length < 2) return videos;'),
      );
    });
  });
}
