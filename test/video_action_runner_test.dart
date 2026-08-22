import 'dart:io';
import 'dart:async';

import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/services/videos/video_action_service.dart';
import 'package:adfoot/videos/domain/video_action_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'video_local_state_test.dart' show makeVideo;

/// One implementation of the six concerns every video action shares, exercised
/// without pumping a widget — which is the point of taking it out of
/// `SmartVideoPlayer`, where none of this could be tested at all.

/// Stands in for the callables. Records what was asked and answers on demand.
class _FakeVideoActionService implements VideoActionService {
  _FakeVideoActionService();

  final List<String> calls = <String>[];
  final Map<String, List<ActionResponse>> queued =
      <String, List<ActionResponse>>{};

  /// Held open so a test can observe the in-flight window.
  Completer<void>? gate;

  void answer(String functionName, List<ActionResponse> responses) {
    queued[functionName] = List<ActionResponse>.of(responses);
  }

  @override
  Future<ActionResponse> callAction(
    String functionName,
    Map<String, dynamic> payload, {
    String? offlineMessage,
  }) async {
    calls.add(functionName);
    final pending = gate;
    if (pending != null) {
      await pending.future;
    }

    final responses = queued[functionName];
    if (responses == null || responses.isEmpty) {
      return ActionResponse.failure(message: 'no stub', code: 'unknown');
    }
    return responses.length == 1 ? responses.first : responses.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ActionResponse liked(bool value) => ActionResponse(
  success: true,
  code: 'liked',
  message: 'ok',
  data: {'liked': value},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeVideoActionService service;
  late VideoController videoController;
  late VideoActionRunner runner;
  late Video video;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _FakeVideoActionService();
    videoController = VideoController(
      contextKey: 'action-runner-test',
      enableLiveStream: false,
      enableFeedFetch: false,
      videoActionService: service,
    );
    runner = VideoActionRunner(
      videoController: videoController,
      followController: FollowController(),
    );
    video = makeVideo();
    videoController.replaceVideos([video]);
  });

  tearDown(() => runner.dispose());

  group('the like shows before it is confirmed', () {
    test('the heart changes immediately, and settles on the server answer',
        () async {
      service.answer('likeVideo', [liked(true)]);

      final pending = runner.toggleLike(video: video, userId: 'viewer');

      // Before the callable has answered.
      expect(videoController.hydrate(video).likes, ['viewer']);
      expect(videoController.hasPendingLocalStateForTests('v1'), isTrue);

      await pending;

      expect(videoController.hydrate(video).likes, ['viewer']);
      expect(
        videoController.hasPendingLocalStateForTests('v1'),
        isFalse,
        reason: 'a settled value must yield to the next server document',
      );
    });

    test('a refused like rolls back to what the server last confirmed',
        () async {
      service.answer('likeVideo', [
        ActionResponse.failure(message: 'nope', code: 'internal'),
      ]);

      await runner.toggleLike(video: video, userId: 'viewer');

      expect(
        videoController.hydrate(video).likes,
        isEmpty,
        reason: 'the optimistic heart must not survive a refusal',
      );
      expect(videoController.hasPendingLocalStateForTests('v1'), isFalse);
    });

    // The reconciliation loop's exit condition is "the server's answer equals
    // the target the user last asked for". That only ever terminates while
    // the server *toggles*. A path that answers with a stable value the
    // target disagrees with — a fallback that sets instead of flipping, a
    // rule refusing the like while still reporting success — used to spin
    // forever, one `likeVideo` callable per turn, silently, for as long as
    // the video stayed on screen. Nothing failed, so nothing was logged.
    test('a server that will not agree is given up on, not retried forever',
        () async {
      // Answers "not liked" no matter how many times it is asked.
      service.answer('likeVideo', [liked(false)]);

      await runner
          .toggleLike(video: video, userId: 'viewer')
          .timeout(const Duration(seconds: 5));

      expect(
        videoController.hydrate(video).likes,
        isEmpty,
        reason: 'the server is the authority once we stop chasing',
      );
      expect(
        service.calls.where((call) => call == 'likeVideo').length,
        lessThanOrEqualTo(3),
        reason: 'an unbounded loop would have called it thousands of times',
      );
      expect(runner.isRunning(VideoAction.like), isFalse);
    });

    // A double tap must not fire two requests, and must not be swallowed
    // either: the second tap becomes the target the loop reconciles to.
    test('a double tap collapses into one request and one final state',
        () async {
      service.gate = Completer<void>();
      service.answer('likeVideo', [liked(true), liked(false)]);

      final first = runner.toggleLike(video: video, userId: 'viewer');
      expect(videoController.hydrate(video).likes, ['viewer']);

      final second = runner.toggleLike(video: video, userId: 'viewer');
      expect(videoController.hydrate(video).likes, isEmpty);

      service.gate!.complete();
      await Future.wait([first, second]);

      expect(service.calls.where((c) => c == 'likeVideo').length, 2);
      expect(videoController.hydrate(video).likes, isEmpty);
      expect(runner.isRunning(VideoAction.like), isFalse);
    });
  });

  group('one action at a time', () {
    test('a second report while one is running is refused, not queued',
        () async {
      service.gate = Completer<void>();
      service.answer('reportVideo', [
        ActionResponse(success: true, code: 'reported', message: 'ok'),
      ]);

      final first = runner.report(video: video, userId: 'viewer');
      expect(runner.isRunning(VideoAction.report), isTrue);

      final refused = await runner.report(video: video, userId: 'viewer');
      expect(refused, isNull, reason: 'the guard reports the refusal');

      service.gate!.complete();
      await first;

      expect(service.calls.where((c) => c == 'reportVideo').length, 1);
      expect(runner.isRunning(VideoAction.report), isFalse);
    });

    test('the in-flight flag is released even when the call throws', () async {
      service.answer('shareVideo', [
        ActionResponse.failure(message: 'boom', code: 'internal'),
      ]);

      await runner.recordShare(video: video);

      expect(runner.isRunning(VideoAction.share), isFalse);
      expect(runner.isBusy, isFalse);
    });

    test('listeners are told when an action starts and stops', () async {
      service.gate = Completer<void>();
      service.answer('reportVideo', [
        ActionResponse(success: true, code: 'reported', message: 'ok'),
      ]);

      var notifications = 0;
      runner.addListener(() => notifications++);

      final pending = runner.report(video: video, userId: 'viewer');
      expect(notifications, greaterThan(0));

      service.gate!.complete();
      await pending;

      expect(runner.isRunning(VideoAction.report), isFalse);
    });
  });

  group('following a publisher', () {
    test('following yourself is refused without calling anything', () async {
      final own = makeVideo(id: 'mine');

      final followed = await runner.followPublisher(
        video: own,
        currentUserId: own.uid,
        isAlreadyFollowing: false,
      );

      expect(followed, isFalse);
      expect(service.calls, isEmpty);
    });

    test('following someone you already follow is refused', () async {
      final followed = await runner.followPublisher(
        video: video,
        currentUserId: 'viewer',
        isAlreadyFollowing: true,
      );

      expect(followed, isFalse);
      expect(service.calls, isEmpty);
    });
  });

  group('the video chain can be built without a Firebase app', () {
    // Four times in this refactor a test could not construct the object it
    // meant to exercise, because a repository resolved a Firebase singleton
    // in its constructor: VideoRepository, VideoActionService,
    // UploadVideoRepository, FollowRepository — and ClientLogger, which is
    // worse, because it is the thing that reports failures and it threw its
    // own exception on a path reached before Firebase was up, burying the
    // error it had been handed.
    //
    // A collaborator that cannot exist without its backend cannot be tested
    // by anybody, and forces every test into an integration test.
    test('no video-chain service resolves Firebase in its constructor', () {
      const chain = <String>[
        'lib/services/videos/video_repository.dart',
        'lib/services/videos/video_action_service.dart',
        'lib/services/videos/upload_video_repository.dart',
        'lib/services/users/follow_repository.dart',
        'lib/services/client_logger.dart',
        'lib/services/feature_flag_service.dart',
      ];

      final eager = RegExp(
        r'^\s*(final|late final)\s+Firebase\w+\s+_?\w+\s*=\s*Firebase'
        r'|^\s*:\s*_?\w+\s*=\s*\w*\s*\?\?\s*Firebase'
        r'|^\s*_?\w+\s*=\s*Firebase\w+\.instance',
      );

      final offenders = <String>[];
      for (final path in chain) {
        final lines = File(path).readAsStringSync().split('\n');
        for (final line in lines) {
          if (line.trimLeft().startsWith('//')) continue;
          // A getter is the fix, not the defect.
          if (line.contains('=>')) continue;
          if (eager.hasMatch(line)) {
            offenders.add('$path: ${line.trim()}');
          }
        }
      }

      expect(offenders, isEmpty);
    });
  });
}
