import 'package:adfoot/models/video.dart';
import 'package:adfoot/videos/domain/network_profile.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lowMp4 = VideoSource(
    url: 'https://cdn.example.com/video_360.mp4',
    quality: '360p',
    type: 'mp4',
    height: 360,
    bitrate: 450000,
  );
  const mediumMp4 = VideoSource(
    url: 'https://cdn.example.com/video_480.mp4',
    quality: '480p',
    type: 'mp4',
    height: 480,
    bitrate: 900000,
  );
  const highMp4 = VideoSource(
    url: 'https://cdn.example.com/video_720.mp4',
    quality: '720p',
    type: 'mp4',
    height: 720,
    bitrate: 1800000,
  );
  const mp4Sources = <VideoSource>[
    lowMp4,
    mediumMp4,
    highMp4,
  ];

  late VideoManager manager;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    manager = VideoManager();
    manager.resetNetworkProfileStateForTests();
  });

  tearDown(() {
    manager.resetNetworkProfileStateForTests();
  });

  test('MP4 requests reuse existing controllers normally', () {
    expect(
      manager.shouldReuseControllerForRequest(
        originalUrl: 'https://cdn.example.com/video.mp4',
        resolvedUrl: 'https://cdn.example.com/video_720.mp4',
        sources: mp4Sources,
        isPreload: false,
      ),
      isTrue,
    );
  });

  test('active playback upgrades from 360p to preferred source on high tier',
      () {
    manager.resetNetworkProfileStateForTests(
      profile: const NetworkProfile(
        tier: NetworkProfileTier.high,
        hasConnection: true,
      ),
    );
    manager.updateAdaptiveFlag(true);

    expect(
      manager.shouldReuseControllerForRequest(
        originalUrl: mediumMp4.url,
        resolvedUrl: lowMp4.url,
        sources: mp4Sources,
        isPreload: false,
      ),
      isFalse,
    );
  });

  test('active playback keeps higher rendition when profile later drops', () {
    manager.resetNetworkProfileStateForTests(
      profile: const NetworkProfile(
        tier: NetworkProfileTier.medium,
        hasConnection: true,
      ),
    );
    manager.updateAdaptiveFlag(true);

    expect(
      manager.shouldReuseControllerForRequest(
        originalUrl: mediumMp4.url,
        resolvedUrl: highMp4.url,
        sources: mp4Sources,
        isPreload: false,
      ),
      isTrue,
    );
  });

  test('file-backed Firebase MP4 failures force a fresh download retry', () {
    expect(
      manager.shouldForceFreshDownloadAfterPrimaryInitFailureForTests(
        usedStreaming: false,
        isPreload: false,
        url: highMp4.url
            .replaceFirst('cdn.example.com', 'firebasestorage.googleapis.com'),
      ),
      isTrue,
    );

    expect(
      manager.shouldForceFreshDownloadAfterPrimaryInitFailureForTests(
        usedStreaming: true,
        isPreload: false,
        url: highMp4.url
            .replaceFirst('cdn.example.com', 'firebasestorage.googleapis.com'),
      ),
      isFalse,
    );
  });

  test('background cache warmup waits until stream init succeeds', () {
    expect(
      manager.shouldWarmCacheAfterStreamInitForTests(
        isPreload: false,
        usedStreaming: true,
        usedStreamFallback: false,
      ),
      isTrue,
    );

    expect(
      manager.shouldWarmCacheAfterStreamInitForTests(
        isPreload: false,
        usedStreaming: true,
        usedStreamFallback: true,
      ),
      isFalse,
    );
  });

  test('purging resolved UI tracking uses a snapshot and avoids map mutation',
      () {
    const contextKey = 'feed';
    const resolvedUrl = 'https://cdn.example.com/video_720.mp4';

    manager.seedResolvedUrlForTests(
      contextKey,
      'https://cdn.example.com/video_a.mp4',
      resolvedUrl,
    );
    manager.seedResolvedUrlForTests(
      contextKey,
      'https://cdn.example.com/video_b.mp4',
      resolvedUrl,
    );

    expect(
      () => manager.purgeResolvedUiTrackingForTests(contextKey, resolvedUrl),
      returnsNormally,
    );
  });
}
