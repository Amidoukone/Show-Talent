import 'dart:io';

import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `VideoController` is the only writer of a video's social state.
///
/// It was not. Eleven call sites mutated `Video` in place, five of them from
/// `SmartVideoPlayer` and five from this controller, and they only agreed
/// when they happened to hold the same instance. A search result and a feed
/// entry are two objects built from the same document, so liking a video in
/// the search results left the feed's copy on the old count — and the crash
/// that finally surfaced in production (`UnmodifiableListMixin.removeWhere`)
/// was the same design showing itself a different way.
Video makeVideo({
  String id = 'v1',
  List<String> likes = const <String>[],
  int shareCount = 0,
  List<String> reports = const <String>[],
  int reportCount = 0,
}) {
  return Video(
    id: id,
    videoUrl: 'https://example.test/$id.mp4',
    thumbnailUrl: '',
    description: '',
    caption: '',
    profilePhoto: '',
    uid: 'author',
    likes: likes,
    shareCount: shareCount,
    reports: reports,
    reportCount: reportCount,
    status: 'ready',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller = VideoController(
      contextKey: 'local-state-test',
      enableLiveStream: false,
      enableFeedFetch: false,
    );
  });

  group('local state follows the document, not the object', () {
    test('a like applied on one instance is seen on every other', () {
      // The feed's copy and the search's copy: same document, two objects.
      final feedCopy = makeVideo();
      final searchCopy = makeVideo();
      expect(identical(feedCopy, searchCopy), isFalse);

      controller.replaceVideos([feedCopy]);
      controller.applyLocalVideoState(
        searchCopy,
        (current) => current.withLike('viewer', liked: true),
        pending: true,
      );

      expect(controller.hydrate(searchCopy).likes, ['viewer']);
      expect(
        controller.hydrate(feedCopy).likes,
        ['viewer'],
        reason: 'in-place mutation could never have reached this instance',
      );
      expect(controller.videoList.single.likes, ['viewer']);
    });

    test('a video the controller has never seen is returned untouched', () {
      final stranger = makeVideo(id: 'other');
      expect(identical(controller.hydrate(stranger), stranger), isTrue);
    });
  });

  group('an optimistic value survives exactly as long as it should', () {
    test('a pending value is not overwritten by an incoming snapshot', () {
      final video = makeVideo();
      controller.replaceVideos([video]);

      controller.applyLocalVideoState(
        video,
        (current) => current.withLike('viewer', liked: true),
        pending: true,
      );

      // The live stream fires on *any* video document changing, so a batch
      // carrying this video's pre-tap counters arrives constantly. Letting it
      // win is what made the heart flip back and forth.
      controller.applyLiveWindowForTests([makeVideo()]);

      expect(controller.videoList.single.likes, ['viewer']);
      expect(controller.hasPendingLocalStateForTests('v1'), isTrue);
    });

    test('a settled value yields to the server', () {
      final video = makeVideo();
      controller.replaceVideos([video]);

      controller.applyLocalVideoState(
        video,
        (current) => current.withLike('viewer', liked: true),
        pending: false,
      );
      expect(controller.videoList.single.likes, ['viewer']);

      // The callable has answered; the next document is the truth, whatever
      // it says.
      controller.applyLiveWindowForTests([makeVideo(likes: const ['someone'])]);

      expect(controller.videoList.single.likes, ['someone']);
      expect(controller.hasPendingLocalStateForTests('v1'), isFalse);
    });

    test('replaceVideos hydrates what it is given', () {
      final video = makeVideo();
      controller.replaceVideos([video]);
      controller.applyLocalVideoState(
        video,
        (current) => current.withShare(),
        pending: true,
      );

      // Reopening the same feed from a fresh snapshot must not lose the share
      // the user just made.
      controller.replaceVideos([makeVideo()]);

      expect(controller.videoList.single.shareCount, 1);
    });
  });

  group('the model is the only place this state can change', () {
    test('no in-place mutation survives anywhere in lib/', () {
      final offenders = <String>[];
      final mutations = RegExp(
        r'\.(likes|reports)\.(add|remove|removeWhere|clear)\(|'
        r'\.(shareCount|reportCount)\s*=\s*[^=]|'
        r'\.resolvedUrl\s*=\s*[^=]',
      );

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        // The model's own constructor defaults are declarations, not writes.
        if (path == 'lib/models/video.dart') continue;

        for (final line in entity.readAsStringSync().split('\n')) {
          if (line.trimLeft().startsWith('//')) continue;
          if (mutations.hasMatch(line)) {
            offenders.add('$path: ${line.trim()}');
          }
        }
      }

      expect(offenders, isEmpty);
    });
  });
}
