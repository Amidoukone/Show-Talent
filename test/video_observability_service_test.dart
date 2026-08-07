import 'package:adfoot/services/video_observability_service.dart';
import 'package:flutter_test/flutter_test.dart';

class LoggedCall {
  LoggedCall({
    required this.source,
    required this.message,
    required this.metadata,
  });

  final String source;
  final String message;
  final Map<String, dynamic>? metadata;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('video action failures are normalized for production queries', () async {
    final errors = <LoggedCall>[];
    final actionLogs = <Map<String, dynamic>>[];
    final service = VideoObservabilityService(
      logError: (source, message, {metadata}) async {
        errors.add(
          LoggedCall(source: source, message: message, metadata: metadata),
        );
      },
      videoActionLog: (payload) async {
        actionLogs.add(payload);
      },
    );

    await service.logActionFailure(
      action: 'likeVideo',
      videoId: 'video-1',
      code: 'permission-denied',
      message: 'Denied',
      metadata: {'contextKey': 'home'},
    );

    expect(errors, hasLength(1));
    expect(errors.single.source, 'video_action');
    expect(errors.single.message, 'like_failed');
    expect(errors.single.metadata?['event'], 'like_failed');
    expect(errors.single.metadata?['contextKey'], 'home');
    expect(actionLogs.single['action'], 'like_failed');
    expect(actionLogs.single['status'], 'failure');
    expect(actionLogs.single['videoId'], 'video-1');
    expect(actionLogs.single['code'], 'permission-denied');
  });

  test('playback retry and play errors use distinct observable events',
      () async {
    final info = <LoggedCall>[];
    final errors = <LoggedCall>[];
    final actionLogs = <Map<String, dynamic>>[];
    final service = VideoObservabilityService(
      logInfo: (source, message, {metadata}) async {
        info.add(
          LoggedCall(source: source, message: message, metadata: metadata),
        );
      },
      logError: (source, message, {metadata}) async {
        errors.add(
          LoggedCall(source: source, message: message, metadata: metadata),
        );
      },
      videoActionLog: (payload) async {
        actionLogs.add(payload);
      },
    );

    await service.logPlaybackRetry(
      videoId: 'video-2',
      videoUrl: 'https://cdn.example.com/video.mp4',
      contextKey: 'home',
      reason: 'manual_retry',
      purgeCachedFile: true,
    );
    await service.logPlaybackError(
      videoId: 'video-2',
      videoUrl: 'https://cdn.example.com/video.mp4',
      contextKey: 'home',
      reason: 'play_error',
      error: Exception('native player failed'),
    );

    expect(info.single.source, 'video_playback');
    expect(info.single.message, 'retry');
    expect(info.single.metadata?['reason'], 'manual_retry');
    expect(errors.single.source, 'video_playback');
    expect(errors.single.message, 'play_error');
    expect(errors.single.metadata?['reason'], 'play_error');
    expect(actionLogs.map((payload) => payload['action']), [
      'retry',
      'play_error',
    ]);
  });

  test('upload failures include stage and session details', () async {
    final errors = <LoggedCall>[];
    final actionLogs = <Map<String, dynamic>>[];
    final service = VideoObservabilityService(
      logError: (source, message, {metadata}) async {
        errors.add(
          LoggedCall(source: source, message: message, metadata: metadata),
        );
      },
      videoActionLog: (payload) async {
        actionLogs.add(payload);
      },
    );

    await service.logUploadFailure(
      stage: 'Téléversement...',
      sessionId: 'session-1',
      code: 'http-503',
      error: 'Service unavailable',
      metadata: {'progress': 0.42},
    );

    expect(errors.single.source, 'video_upload');
    expect(errors.single.message, 'upload_failed');
    expect(errors.single.metadata?['stage'], 'Téléversement...');
    expect(errors.single.metadata?['progress'], 0.42);
    expect(actionLogs.single['action'], 'upload_failed');
    expect(actionLogs.single['videoId'], 'session-1');
    expect(actionLogs.single['code'], 'http-503');
  });
}
