import 'package:adfoot/services/video_metrics_observer.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class LoggedMetricCall {
  LoggedMetricCall({
    required this.source,
    required this.message,
    required this.metadata,
  });

  final String source;
  final String message;
  final Map<String, dynamic>? metadata;
}

Future<void> flushMicrotasks([int times = 3]) async {
  for (int i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('errors are always emitted even when success sampling is disabled',
      () async {
    final infoCalls = <LoggedMetricCall>[];
    final errorCalls = <LoggedMetricCall>[];
    final observer = VideoMetricsObserver(
      policy: const VideoMetricsPolicy(successSampleRate: 0),
      logInfo: (source, message, {metadata}) async {
        infoCalls.add(
          LoggedMetricCall(
            source: source,
            message: message,
            metadata: metadata,
          ),
        );
      },
      logError: (source, message, {metadata}) async {
        errorCalls.add(
          LoggedMetricCall(
            source: source,
            message: message,
            metadata: metadata,
          ),
        );
      },
    );

    observer.handle(
      VideoMetricEvent(
        type: VideoMetricType.initError,
        url: 'https://cdn.example.com/video.mp4',
        isPreload: false,
        error: Exception('boom'),
      ),
    );
    await flushMicrotasks();

    expect(infoCalls, isEmpty);
    expect(errorCalls, hasLength(1));
    expect(errorCalls.single.source, 'video_manager');
    expect(errorCalls.single.message, 'Video init error');
    expect(errorCalls.single.metadata?['url'],
        'https://cdn.example.com/video.mp4');
  });

  test('success metrics are skipped in errors-only mode', () async {
    final infoCalls = <LoggedMetricCall>[];
    final observer = VideoMetricsObserver(
      policy: const VideoMetricsPolicy(successSampleRate: 0),
      logInfo: (source, message, {metadata}) async {
        infoCalls.add(
          LoggedMetricCall(
            source: source,
            message: message,
            metadata: metadata,
          ),
        );
      },
      logError: (source, message, {metadata}) async {},
    );

    observer.handle(
      VideoMetricEvent(
        type: VideoMetricType.initSuccess,
        url: 'https://cdn.example.com/video.mp4',
        isPreload: false,
        usedCache: true,
      ),
    );
    await flushMicrotasks();

    expect(infoCalls, isEmpty);
  });

  test(
      'preload success metrics can be filtered while active metrics still pass',
      () async {
    final infoCalls = <LoggedMetricCall>[];
    final observer = VideoMetricsObserver(
      policy: const VideoMetricsPolicy(
        successSampleRate: 1,
        includePreloadSuccess: false,
      ),
      logInfo: (source, message, {metadata}) async {
        infoCalls.add(
          LoggedMetricCall(
            source: source,
            message: message,
            metadata: metadata,
          ),
        );
      },
      logError: (source, message, {metadata}) async {},
    );

    observer.handle(
      VideoMetricEvent(
        type: VideoMetricType.initSuccess,
        url: 'https://cdn.example.com/preload.mp4',
        isPreload: true,
      ),
    );
    observer.handle(
      VideoMetricEvent(
        type: VideoMetricType.initSuccess,
        url: 'https://cdn.example.com/active.mp4',
        isPreload: false,
      ),
    );
    await flushMicrotasks();

    expect(infoCalls, hasLength(1));
    expect(infoCalls.single.metadata?['isPreload'], isFalse);
    expect(infoCalls.single.metadata?['url'],
        'https://cdn.example.com/active.mp4');
  });

  test('success metrics include HLS playback metadata', () async {
    final infoCalls = <LoggedMetricCall>[];
    final observer = VideoMetricsObserver(
      policy: const VideoMetricsPolicy(successSampleRate: 1),
      logInfo: (source, message, {metadata}) async {
        infoCalls.add(
          LoggedMetricCall(
            source: source,
            message: message,
            metadata: metadata,
          ),
        );
      },
      logError: (source, message, {metadata}) async {},
    );

    observer.handle(
      VideoMetricEvent(
        type: VideoMetricType.initSuccess,
        url: 'https://cdn.example.com/video.mp4',
        isPreload: false,
        contextKey: 'home',
        sourceType: 'mp4',
        sourceQuality: '480p',
        sourceHeight: 480,
        sourceBitrate: 1000000,
        requestedHls: true,
        cacheBypassed: true,
        playbackBranch: 'hls_network_direct',
        hlsSuppressedReason: 'android_preload_uses_mp4',
        manifestHost: 'firebasestorage.googleapis.com',
        manifestPath: '/v0/b/project.appspot.com/o/hls%2Fvideo%2Fmaster.m3u8',
        manifestHasToken: true,
        usedStreaming: true,
        usedStreamFallback: true,
        fallbackFromSourceType: 'hls',
        recoveryReason: 'stall_watchdog',
        primaryInitDuration: const Duration(seconds: 12),
        fallbackDownloadDuration: const Duration(seconds: 4),
        fallbackInitDuration: const Duration(milliseconds: 900),
        fallbackCacheHit: false,
        reusedInFlightDownload: true,
      ),
    );
    await flushMicrotasks();

    expect(infoCalls, hasLength(1));
    expect(infoCalls.single.metadata?['entryContext'], 'home');
    expect(infoCalls.single.metadata?['sourceType'], 'mp4');
    expect(infoCalls.single.metadata?['requestedHls'], isTrue);
    expect(infoCalls.single.metadata?['cacheBypassed'], isTrue);
    expect(infoCalls.single.metadata?['playbackBranch'], 'hls_network_direct');
    expect(
      infoCalls.single.metadata?['hlsSuppressedReason'],
      'android_preload_uses_mp4',
    );
    expect(
      infoCalls.single.metadata?['manifestHost'],
      'firebasestorage.googleapis.com',
    );
    expect(
      infoCalls.single.metadata?['manifestPath'],
      '/v0/b/project.appspot.com/o/hls%2Fvideo%2Fmaster.m3u8',
    );
    expect(infoCalls.single.metadata?['manifestHasToken'], isTrue);
    expect(infoCalls.single.metadata?['usedStreamFallback'], isTrue);
    expect(infoCalls.single.metadata?['fallbackFromSourceType'], 'hls');
    expect(infoCalls.single.metadata?['recoveryReason'], 'stall_watchdog');
    expect(infoCalls.single.metadata?['primaryInitDurationMs'], 12000);
    expect(infoCalls.single.metadata?['fallbackDownloadDurationMs'], 4000);
    expect(infoCalls.single.metadata?['fallbackInitDurationMs'], 900);
    expect(infoCalls.single.metadata?['fallbackCacheHit'], isFalse);
    expect(infoCalls.single.metadata?['reusedInFlightDownload'], isTrue);
  });

  test('success metrics honor the configured sample rate', () async {
    final infoCalls = <LoggedMetricCall>[];
    final observer = VideoMetricsObserver(
      policy: const VideoMetricsPolicy(successSampleRate: 0.25),
      random: () => 0.9,
      logInfo: (source, message, {metadata}) async {
        infoCalls.add(
          LoggedMetricCall(
            source: source,
            message: message,
            metadata: metadata,
          ),
        );
      },
      logError: (source, message, {metadata}) async {},
    );

    observer.handle(
      VideoMetricEvent(
        type: VideoMetricType.initSuccess,
        url: 'https://cdn.example.com/video.mp4',
        isPreload: false,
      ),
    );
    await flushMicrotasks();

    expect(infoCalls, isEmpty);
  });
}
