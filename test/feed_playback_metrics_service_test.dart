import 'package:adfoot/models/video.dart';
import 'package:adfoot/services/feed_playback_metrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

class LoggedPlaybackCall {
  LoggedPlaybackCall({
    required this.source,
    required this.message,
    required this.metadata,
  });

  final String source;
  final String message;
  final Map<String, dynamic>? metadata;
}

void main() {
  test('tracker computes first frame, completion, and estimated bytes', () {
    var now = DateTime.utc(2026, 3, 20, 12);
    final tracker = FeedPlaybackSessionTracker(
      videoId: 'video-1',
      entryContext: 'home',
      now: () => now,
      playbackMode: 'multi_rendition_mp4',
      networkTier: 'medium',
      preferHlsRequested: false,
      resolvedUrl: 'https://cdn.example.com/mp4/video-1/480p.mp4',
      source: const VideoSource(
        url: 'https://cdn.example.com/mp4/video-1/480p.mp4',
        type: 'mp4',
        quality: '480p',
        height: 480,
        bitrate: 800000,
      ),
    );

    tracker.recordPlaybackSample(
      position: Duration.zero,
      duration: const Duration(seconds: 10),
      isBuffering: false,
    );

    now = now.add(const Duration(milliseconds: 300));
    tracker.markFirstFrameRendered();

    now = now.add(const Duration(seconds: 1));
    tracker.recordPlaybackSample(
      position: const Duration(seconds: 1),
      duration: const Duration(seconds: 10),
      isBuffering: false,
    );

    now = now.add(const Duration(seconds: 8));
    tracker.recordPlaybackSample(
      position: const Duration(seconds: 9),
      duration: const Duration(seconds: 10),
      isBuffering: false,
    );

    final summary = tracker.finish(endReason: 'passive');

    expect(summary.timeToFirstFrame?.inMilliseconds, 300);
    expect(summary.completed, isTrue);
    expect(summary.completionRate, 1.0);
    expect(summary.watchDuration.inMilliseconds, 9000);
    expect(summary.estimatedBytesPlayed, 900000);
    expect(summary.finalSourceBitrate, 800000);
    expect(summary.networkTier, 'medium');
  });

  test('tracker captures rebuffer duration and recovery success', () {
    var now = DateTime.utc(2026, 3, 20, 12);
    final tracker = FeedPlaybackSessionTracker(
      videoId: 'video-2',
      entryContext: 'profile:user-1',
      now: () => now,
      resolvedUrl: 'https://cdn.example.com/mp4/video-2/720p.mp4',
      source: const VideoSource(
        url: 'https://cdn.example.com/mp4/video-2/720p.mp4',
        type: 'mp4',
        quality: '720p',
        height: 720,
        bitrate: 1800000,
      ),
    );

    now = now.add(const Duration(milliseconds: 500));
    tracker.markFirstFrameRendered();

    tracker.recordPlaybackSample(
      position: const Duration(seconds: 1),
      duration: const Duration(seconds: 12),
      isBuffering: false,
    );

    now = now.add(const Duration(seconds: 2));
    tracker.recordPlaybackSample(
      position: const Duration(seconds: 1),
      duration: const Duration(seconds: 12),
      isBuffering: true,
    );
    tracker.recordRecoveryAttempt('stall_watchdog');

    now = now.add(const Duration(seconds: 3));
    tracker.recordPlaybackSample(
      position: const Duration(seconds: 1),
      duration: const Duration(seconds: 12),
      isBuffering: false,
    );

    now = now.add(const Duration(milliseconds: 200));
    tracker.markFirstFrameRendered();

    final summary = tracker.finish(endReason: 'passive');

    expect(summary.rebufferCount, 1);
    expect(summary.rebufferDuration.inMilliseconds, 3000);
    expect(summary.stallRecoveryCount, 1);
    expect(summary.stallRecoverySuccessCount, 1);
    expect(summary.stallRecoveryRate, 1.0);
    expect(summary.recoveryReasons, {'stall_watchdog': 1});
  });

  test('tracker normalizes legacy HLS contracts to runtime MP4 mode', () {
    var now = DateTime.utc(2026, 3, 20, 12);
    final tracker = FeedPlaybackSessionTracker(
      videoId: 'video-legacy',
      entryContext: 'home',
      now: () => now,
      playbackMode: 'multi_rendition_hls',
      hasMultipleMp4Sources: true,
      resolvedUrl: 'https://cdn.example.com/mp4/video-legacy/720p.mp4',
      source: const VideoSource(
        url: 'https://cdn.example.com/mp4/video-legacy/720p.mp4',
        type: 'mp4',
        quality: '720p',
        height: 720,
        bitrate: 1800000,
      ),
    );

    now = now.add(const Duration(milliseconds: 250));
    tracker.markFirstFrameRendered();
    tracker.recordPlaybackSample(
      position: const Duration(seconds: 2),
      duration: const Duration(seconds: 12),
      isBuffering: false,
    );

    final summary = tracker.finish(endReason: 'passive');

    expect(summary.playbackMode, 'multi_rendition_mp4');
    expect(summary.contractPlaybackMode, 'multi_rendition_hls');
    expect(summary.finalSourceType, 'mp4');
  });

  test('logger samples clean sessions but always keeps problematic ones',
      () async {
    final infoCalls = <LoggedPlaybackCall>[];
    final logger = FeedPlaybackMetricsLogger(
      policy: const FeedPlaybackMetricsPolicy(sampleRate: 0),
      random: () => 0.9,
      emitInfo: (source, message, {metadata}) async {
        infoCalls.add(
          LoggedPlaybackCall(
            source: source,
            message: message,
            metadata: metadata,
          ),
        );
      },
    );

    await logger.logSession(
      const FeedPlaybackSessionSummary(
        videoId: 'clean',
        entryContext: 'home',
        sessionDuration: Duration(seconds: 5),
        watchDuration: Duration(seconds: 4),
        hadFirstFrame: true,
        completed: false,
        completionRate: 0,
        rebufferCount: 0,
        rebufferDuration: Duration.zero,
        rebufferRate: 0,
        stallRecoveryCount: 0,
        stallRecoverySuccessCount: 0,
        estimatedBytesPlayed: 1000,
        endReason: 'passive',
      ),
    );

    await logger.logSession(
      const FeedPlaybackSessionSummary(
        videoId: 'problem',
        entryContext: 'home',
        sessionDuration: Duration(seconds: 5),
        watchDuration: Duration(seconds: 2),
        hadFirstFrame: true,
        completed: false,
        completionRate: 0,
        rebufferCount: 1,
        rebufferDuration: Duration(seconds: 1),
        rebufferRate: 0.5,
        stallRecoveryCount: 0,
        stallRecoverySuccessCount: 0,
        estimatedBytesPlayed: 500,
        endReason: 'passive',
      ),
    );

    expect(infoCalls, hasLength(1));
    expect(infoCalls.single.source, 'feed_playback');
    expect(infoCalls.single.message, 'Feed playback session');
    expect(infoCalls.single.metadata?['videoId'], 'problem');
  });
}
