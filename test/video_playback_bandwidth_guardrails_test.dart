import 'dart:io';

import 'package:adfoot/models/video.dart';
import 'package:adfoot/videos/domain/network_profile.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guardrails for the playback-bandwidth pass on 1.0.7+20.
///
/// One symptom, reported on every freshly published video since 1.0.7+18: the
/// clip pauses and resumes by itself for its whole duration, then plays
/// perfectly "after a few scrolls". Nothing failed, so nothing was logged.
/// The video was simply never alone on the connection.
///
/// Source-level assertions where the fix is a decision in the code, real ones
/// where the fix is behaviour.
String _read(String path) => File(path).readAsStringSync();

class _StubNetworkProfileService extends NetworkProfileService {
  @override
  Future<NetworkProfile> detectProfile() async {
    return const NetworkProfile(
      tier: NetworkProfileTier.medium,
      hasConnection: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a streamed video is alone on the connection', () {
    late String manager;
    late String player;

    setUpAll(() {
      manager = _read('lib/widgets/video_manager.dart');
      player = _read('lib/widgets/smart_video_player.dart');
    });

    // CachedVideoPlayerPlus.networkUrl() defaults to skipCache: false, and
    // that default is not "reuse the cache" -- it is "start an unawaited
    // downloadFile of this exact URL into my own private cache, then stream
    // the same URL anyway". Two transfers of identical bytes, and the one the
    // user is watching loses.
    test('the streaming branch opts out of the player own cache', () {
      expect(manager, contains('skipCache: true,'));

      final streamIndex = manager.indexOf('usedStreaming = true;');
      expect(streamIndex, isNonNegative);
      final tail = manager.substring(streamIndex);
      expect(
        tail.indexOf('skipCache: true,'),
        isNonNegative,
        reason: 'the opt-out must sit on the branch that streams',
      );
    });

    // A preload is a full file download. Firing the two or three neighbours
    // alongside a live stream starves it just as effectively as the
    // player own duplicate download did.
    test('preloads wait for the active stream to prove itself', () {
      expect(manager, contains('_streamingUrlsByContext'));
      expect(manager, contains('_deferredPreloadsByContext'));
      expect(manager, contains('void markActivePlaybackStable('));
      expect(manager, contains('if (_isStreamingUrl(contextKey, resolvedActive)) {'));
    });

    test('the player reports a healthy stream from the stall watchdog', () {
      expect(player, contains('_smoothPlaybackTicks'));
      expect(player, contains('_reportedPlaybackStable'));
      expect(player, contains('_smoothTicksBeforeStable'));
      expect(player, contains('_videoManager.markActivePlaybackStable('));
      // Once per attached player: re-arming the watchdog must not re-open a
      // question that already has an answer.
      expect(
        player,
        contains('if (_reportedPlaybackStable || !_hasFirstFrame) return;'),
      );
    });

    // Both failures below share a shape: the count silently never reaches its
    // threshold, the neighbours stay deferred for as long as the video is on
    // screen, nothing ever reaches the cache, and no error is raised anywhere.
    test('re-arming the watchdog does not clear the smooth count', () {
      final kick = player.indexOf('void _kickStallWatchdog(');
      expect(kick, isNonNegative);

      // Only the re-arm preamble, not the periodic body: the tick itself
      // still resets the count on buffering and on no progress, which is
      // exactly what it should do.
      final preamble = player.substring(
        kick,
        player.indexOf('_stallTimer = Timer.periodic(', kick),
      );
      expect(
        preamble,
        isNot(contains('_smoothPlaybackTicks = 0;')),
        reason: '_maybePlay re-arms this on any rebuild that reschedules a play',
      );
      // It still belongs to the attached player and to real trouble.
      final bind = player.indexOf('void _bindPlayer(');
      expect(bind, isNonNegative);
      final bindBody = player.substring(bind, bind + 400);
      expect(bindBody, contains('_smoothPlaybackTicks = 0;'));
      expect(bindBody, contains('_reportedPlaybackStable = false;'));
    });

    test('a looping clip is not mistaken for a stalled one', () {
      // Every controller loops, so a clip rewinds to zero once per cycle. A
      // clip shorter than the stability window would otherwise reset on every
      // loop and never report itself healthy.
      expect(player, contains('if (v.position < _lastKnownPos) {'));

      final wrap = player.indexOf('if (v.position < _lastKnownPos) {');
      expect(wrap, isNonNegative);
      expect(
        player.substring(wrap, wrap + 200),
        contains('_reportPlaybackStableIfSmooth();'),
      );
    });
  });

  group('preload arbitration', () {
    late VideoManager manager;
    const contextKey = 'feed-bandwidth-test';
    const activeUrl = 'https://cdn.example.com/active.mp4';

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      manager = VideoManager();
      manager.resetNetworkProfileStateForTests(
        networkProfileService: _StubNetworkProfileService(),
      );
    });

    tearDown(() async {
      manager.markStreamingForTests(
        contextKey,
        activeUrl,
        isStreaming: false,
      );
      await manager.disposeAllForContext(contextKey);
      manager.resetNetworkProfileStateForTests();
    });

    test('a streaming active video defers its neighbours', () async {
      manager.markStreamingForTests(contextKey, activeUrl, isStreaming: true);

      await manager.preloadSurrounding(
        contextKey,
        const <Video>[],
        0,
        activeUrl: activeUrl,
      );

      expect(manager.hasDeferredPreloadForTests(contextKey), isTrue);
    });

    test('a healthy stream releases them again', () async {
      manager.markStreamingForTests(contextKey, activeUrl, isStreaming: true);

      await manager.preloadSurrounding(
        contextKey,
        const <Video>[],
        0,
        activeUrl: activeUrl,
      );
      expect(manager.hasDeferredPreloadForTests(contextKey), isTrue);

      manager.markActivePlaybackStable(contextKey, activeUrl);

      expect(manager.isStreamingUrlForTests(contextKey, activeUrl), isFalse);
      expect(manager.hasDeferredPreloadForTests(contextKey), isFalse);
    });

    test('a cached active video never defers anything', () async {
      await manager.preloadSurrounding(
        contextKey,
        const <Video>[],
        0,
        activeUrl: activeUrl,
      );

      expect(manager.hasDeferredPreloadForTests(contextKey), isFalse);
    });
  });

  group('the video cache has exactly one owner', () {
    late String cache;

    setUpAll(() {
      cache = _read('lib/utils/video_cache_manager.dart');
    });

    // The blobs used to live under getApplicationSupportDirectory(), which
    // Android reports as user data: no "clear cache" could touch them, and
    // the system could never reclaim them under storage pressure. A cache
    // belongs in the cache directory.
    test('blobs live in the OS cache directory', () {
      expect(cache, contains('getTemporaryDirectory()'));
      expect(cache, contains('fileSystem: IOFileSystem(key),'));
      expect(
        cache,
        isNot(contains('Directory.systemTemp')),
        reason: 'the sync factory used to build a cache nobody could find',
      );
    });

    test('the abandoned caches are reclaimed at startup', () {
      final bootstrap = _read('lib/config/app_bootstrap.dart');

      expect(cache, contains("'libCachedVideoPlayerPlusData'"));
      expect(cache, contains('static Future<void> performStartupMaintenance()'));
      expect(
        bootstrap,
        contains('VideoCacheManager.performStartupMaintenance'),
      );
    });

    // Freeing a fixed 50 MB block put the cache back at its ceiling two
    // videos later, so the next download purged again, and the one after
    // that. Purging to a target costs one scan instead of one per download.
    test('a purge aims at a target instead of a fixed block', () {
      expect(cache, contains('static const int maxCacheSizeMB = 600;'));
      expect(cache, contains('static const int targetCacheSizeMB = 420;'));
      expect(cache, isNot(contains('purgeBlockSizeMB')));
      expect(cache, contains('if (remaining <= targetBytes) break;'));
    });

    // Ordering by mtime is ordering by *download* time: a video watched every
    // day was evicted before one downloaded later and never opened again.
    test('eviction order is least-recently-used, not oldest-downloaded', () {
      expect(cache, contains('static Future<void> _markUsed(File file)'));
      expect(cache, contains('setLastAccessed'));
      expect(cache, contains('unawaited(_markUsed(fileInfo.file))'));
      expect(cache, contains('_recentUseGracePeriod'));
      expect(
        cache,
        contains('if (entry.lastUsedAt.isAfter(protectedAfter)) continue;'),
        reason: 'the video on screen and its neighbours are never purged',
      );
    });
  });
}
