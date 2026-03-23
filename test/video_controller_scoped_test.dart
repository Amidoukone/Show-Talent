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

    controller.replaceVideos(
      [
        buildVideo('v1'),
        buildVideo('v2'),
      ],
      selectedIndex: 1,
    );

    expect(controller.videoList.length, 2);
    expect(controller.currentIndex.value, 1);

    final fetched = await controller.fetchPaginatedVideos();
    final refreshed = await controller.refreshVideos();

    expect(fetched, isFalse);
    expect(refreshed, isFalse);
    expect(controller.videoList.length, 2);
    expect(controller.currentIndex.value, 1);
  });

  test('replaceVideos clamps selected index and clears selection on empty list',
      () {
    final controller = VideoController(
      contextKey: 'profile:user-2',
      enableLiveStream: false,
      enableFeedFetch: false,
    );

    controller.replaceVideos(
      [
        buildVideo('v1'),
        buildVideo('v2'),
      ],
      selectedIndex: 7,
    );

    expect(controller.currentIndex.value, 1);

    controller.replaceVideos(const []);

    expect(controller.videoList, isEmpty);
    expect(controller.currentIndex.value, -1);
  });

  test(
      'live feed buffers new head videos while keeping the current order stable',
      () {
    final controller = VideoController(
      contextKey: 'home',
      enableLiveStream: true,
      enableFeedFetch: true,
    );

    controller.replaceVideos(
      [
        buildVideo('v1'),
        buildVideo('v2'),
        buildVideo('v3'),
      ],
      selectedIndex: 2,
    );

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
  });

  test('returning to the top signals that buffered live videos should apply',
      () {
    final controller = VideoController(
      contextKey: 'home',
      enableLiveStream: true,
      enableFeedFetch: true,
    );

    controller.replaceVideos(
      [
        buildVideo('v1'),
        buildVideo('v2'),
        buildVideo('v3'),
      ],
      selectedIndex: 2,
    );

    controller.applyLiveWindowForTests([
      buildVideo('v-new'),
      buildVideo('v1'),
      buildVideo('v2'),
    ]);

    final shouldApplyBufferedLive = controller.updateCurrentIndex(0);
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
  });

  test(
      'manual live apply prepends pending videos only once and can move to top',
      () {
    final controller = VideoController(
      contextKey: 'home',
      enableLiveStream: true,
      enableFeedFetch: true,
    );

    controller.replaceVideos(
      [
        buildVideo('v1'),
        buildVideo('v2'),
      ],
      selectedIndex: 1,
    );

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
  });

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

    controller.replaceVideos(
      [
        buildVideo('v1'),
        buildVideo('v2'),
      ],
      selectedIndex: 1,
    );

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
  });
}
