import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
