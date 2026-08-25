import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> flushMicrotasks([int times = 3]) async {
  for (int i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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

  Video buildVideo(String id, {String? description, String? thumbnailUrl}) {
    return Video(
      id: id,
      videoUrl: 'https://cdn.example.com/$id.mp4',
      thumbnailUrl: thumbnailUrl ?? '',
      description: description ?? 'desc $id',
      caption: 'caption $id',
      profilePhoto: '',
      uid: 'user-$id',
    );
  }

  test('scoped controller does not fetch or refresh global feed', () async {
    final controller = VideoController(
      contextKey: 'profile:user-1',
      enableLiveStream: false,
      enableFeedFetch: false,
    );

    controller.replaceVideos([
      buildVideo('v1'),
      buildVideo('v2'),
    ], selectedIndex: 1);

    expect(controller.videoList.length, 2);
    expect(controller.currentIndex.value, 1);

    final fetched = await controller.fetchPaginatedVideos();
    final refreshed = await controller.refreshVideos();

    expect(fetched, isFalse);
    expect(refreshed, isFalse);
    expect(controller.videoList.length, 2);
    expect(controller.currentIndex.value, 1);
  });

  test(
    'replaceVideos clamps selected index and clears selection on empty list',
    () {
      final controller = VideoController(
        contextKey: 'profile:user-2',
        enableLiveStream: false,
        enableFeedFetch: false,
      );

      controller.replaceVideos([
        buildVideo('v1'),
        buildVideo('v2'),
      ], selectedIndex: 7);

      expect(controller.currentIndex.value, 1);

      controller.replaceVideos(const []);

      expect(controller.videoList, isEmpty);
      expect(controller.currentIndex.value, -1);
    },
  );

  test(
    'live feed buffers new head videos while keeping the current order stable',
    () {
      final controller = VideoController(
        contextKey: 'home',
        enableLiveStream: true,
        enableFeedFetch: true,
      );

      controller.replaceVideos([
        buildVideo('v1'),
        buildVideo('v2'),
        buildVideo('v3'),
      ], selectedIndex: 2);

      controller.applyLiveWindowForTests([
        buildVideo('v-new'),
        buildVideo('v1', description: 'updated v1'),
        buildVideo('v2'),
      ]);

      expect(controller.videoList.map((video) => video.id).toList(), [
        'v1',
        'v2',
        'v3',
      ]);
      expect(controller.videoList.first.description, 'updated v1');
      expect(controller.pendingLiveCount.value, 1);
      expect(controller.currentIndex.value, 2);
    },
  );

  // adfoot-production, 2026-08-24: 14 documents with `status: "ready"`. The
  // feed loads a page of 10 (`_limit`) and the live stream watches 30
  // (`_liveWindowLimit`), so the four documents past page one were in the
  // window, absent from `videoList`, and announced as "4 nouvelles vidéos"
  // before the user had scrolled anywhere. Pagination was always going to
  // bring them in; they were never new.
  test('a live window deeper than the loaded feed announces nothing', () {
    final controller = VideoController(
      contextKey: 'home',
      enableLiveStream: true,
      enableFeedFetch: true,
    );

    final ready = [for (var i = 0; i < 14; i++) buildVideo('ready-$i')];

    // What one page of the feed put on screen.
    controller.replaceVideos(ready.take(10).toList(), selectedIndex: 0);

    // What the live stream sees: the same ordering, four documents deeper.
    controller.applyLiveWindowForTests(ready);

    expect(controller.pendingLiveCount.value, 0);
    expect(controller.videoList.length, 10);
  });

  // Same feed, one genuinely new publication: it sorts above everything the
  // user already has, which is exactly what the banner is for.
  test('a video published above the feed head is announced', () {
    final controller = VideoController(
      contextKey: 'home',
      enableLiveStream: true,
      enableFeedFetch: true,
    );

    final ready = [for (var i = 0; i < 14; i++) buildVideo('ready-$i')];
    controller.replaceVideos(ready.take(10).toList(), selectedIndex: 0);
    controller.applyLiveWindowForTests(ready);
    expect(controller.pendingLiveCount.value, 0);

    controller.applyLiveWindowForTests([buildVideo('just-published'), ...ready]);

    expect(controller.pendingLiveCount.value, 1);
    expect(controller.applyBufferedLiveVideos(moveToTop: true), 1);
    expect(controller.videoList.first.id, 'just-published');
  });

  // Opening a shared link prepends a video fetched by id, so the feed holds
  // one document the page query did not return. The batch that follows must
  // not read that difference as news either.
  test('a deep-linked video does not make the rest of the window new', () {
    final controller = VideoController(
      contextKey: 'home',
      enableLiveStream: true,
      enableFeedFetch: true,
    );

    final ready = [for (var i = 0; i < 14; i++) buildVideo('ready-$i')];
    controller.replaceVideos([
      ready.last,
      ...ready.take(10),
    ], selectedIndex: 0);

    controller.applyLiveWindowForTests(ready);

    expect(controller.pendingLiveCount.value, 0);
  });

  test('live feed activates the first ready video after an empty refresh', () {
    final controller = VideoController(
      contextKey: 'home',
      enableLiveStream: true,
      enableFeedFetch: true,
    );

    controller.replaceVideos(const []);

    controller.applyLiveWindowForTests([buildVideo('newly-approved')]);

    expect(controller.videoList.map((video) => video.id).toList(), [
      'newly-approved',
    ]);
    expect(controller.pendingLiveCount.value, 0);
    expect(controller.currentIndex.value, 0);
  });

  test(
    'returning to the top signals that buffered live videos should apply',
    () {
      final controller = VideoController(
        contextKey: 'home',
        enableLiveStream: true,
        enableFeedFetch: true,
      );

      controller.replaceVideos([
        buildVideo('v1'),
        buildVideo('v2'),
        buildVideo('v3'),
      ], selectedIndex: 2);

      controller.applyLiveWindowForTests([
        buildVideo('v-new'),
        buildVideo('v1'),
        buildVideo('v2'),
      ]);

      // `updateCurrentIndex` wrote the index *and* answered this question in
      // one call, which is why the answer could not survive the index moving
      // into VideoFeedPager: it depends on where the user came from.
      final shouldApplyBufferedLive = controller.shouldSurfacePendingLiveAt(
        previousIndex: controller.currentIndex.value,
        index: 0,
      );
      controller.currentIndex.value = 0;
      final inserted = controller.applyBufferedLiveVideos();

      expect(shouldApplyBufferedLive, isTrue);
      expect(inserted, 1);
      expect(controller.videoList.map((video) => video.id).toList(), [
        'v-new',
        'v1',
        'v2',
        'v3',
      ]);
      expect(controller.pendingLiveCount.value, 0);
      expect(controller.currentIndex.value, 0);
    },
  );

  test(
    'manual live apply prepends pending videos only once and can move to top',
    () {
      final controller = VideoController(
        contextKey: 'home',
        enableLiveStream: true,
        enableFeedFetch: true,
      );

      controller.replaceVideos([
        buildVideo('v1'),
        buildVideo('v2'),
      ], selectedIndex: 1);

      controller.applyLiveWindowForTests([
        buildVideo('v-new'),
        buildVideo('v1'),
      ]);

      final inserted = controller.applyBufferedLiveVideos(moveToTop: true);
      final insertedAgain = controller.applyBufferedLiveVideos(moveToTop: true);

      expect(inserted, 1);
      expect(insertedAgain, 0);
      expect(controller.videoList.map((video) => video.id).toList(), [
        'v-new',
        'v1',
        'v2',
      ]);
      expect(controller.pendingLiveCount.value, 0);
      expect(controller.currentIndex.value, 0);
    },
  );

  test(
    'pending live videos warm only a few thumbnails without mounting players',
    () async {
      final controller = VideoController(
        contextKey: 'home',
        enableLiveStream: true,
        enableFeedFetch: true,
      );
      final prefetched = <String>[];

      controller.setThumbnailPrefetcherForTests((thumbUrl) async {
        prefetched.add(thumbUrl);
      });

      controller.replaceVideos([
        buildVideo('v1'),
        buildVideo('v2'),
      ], selectedIndex: 1);

      controller.applyLiveWindowForTests([
        buildVideo(
          'v-new-1',
          thumbnailUrl: 'https://cdn.example.com/thumbs/1.jpg',
        ),
        buildVideo(
          'v-new-2',
          thumbnailUrl: 'https://cdn.example.com/thumbs/2.jpg',
        ),
        buildVideo(
          'v-new-3',
          thumbnailUrl: 'https://cdn.example.com/thumbs/3.jpg',
        ),
        buildVideo(
          'v-new-4',
          thumbnailUrl: 'https://cdn.example.com/thumbs/4.jpg',
        ),
        buildVideo(
          'v-new-5',
          thumbnailUrl: 'https://cdn.example.com/thumbs/5.jpg',
        ),
      ]);

      await flushMicrotasks();

      expect(controller.pendingLiveCount.value, 5);
      expect(prefetched, [
        'https://cdn.example.com/thumbs/1.jpg',
        'https://cdn.example.com/thumbs/2.jpg',
        'https://cdn.example.com/thumbs/3.jpg',
        'https://cdn.example.com/thumbs/4.jpg',
      ]);
      expect(controller.videoList.map((video) => video.id).toList(), [
        'v1',
        'v2',
      ]);
    },
  );
}
