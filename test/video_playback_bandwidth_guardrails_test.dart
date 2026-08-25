import 'dart:io';

import 'package:adfoot/models/video.dart';
import 'package:adfoot/videos/domain/network_profile.dart';
import 'package:adfoot/videos/video_manager.dart';
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
      manager = _read('lib/videos/video_manager.dart');
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
    //
    // The decision now lives in PlaybackBandwidthArbiter rather than inside
    // VideoManager. It is a decision with an incident behind it, not
    // plumbing, and it earned a name; the behavioural tests below are what
    // actually prove it still holds.
    test('preloads wait for the active stream to prove itself', () {
      final arbiter = _read('lib/videos/domain/playback_bandwidth_arbiter.dart');

      expect(arbiter, contains('class PlaybackBandwidthArbiter'));
      expect(arbiter, contains('_streamingUrlsByContext'));
      expect(arbiter, contains('_deferredByContext'));
      expect(manager, contains('void markActivePlaybackStable('));
      expect(
        manager,
        contains('if (_isStreamingUrl(contextKey, resolvedActive)) {'),
      );
      expect(manager, contains('_bandwidth.defer('));
    });

    // The other half of the same decision. A preload that downloads the whole
    // file is a bet that the transfer finishes before the swipe does, and
    // adfoot-production's catalogue does not let that bet be won: the
    // heaviest ready video is 71 MB at 10.6 Mb/s with no lighter rendition,
    // against a preload timeout of 8-12 s. On 2026-08-24 its client_logs show
    // 18 playback sessions, 7 of them with `timeToFirstFrameMs: null` -- no
    // frame ever rendered.
    test('a preload prepares a stream, not a whole file', () {
      final marker = manager.indexOf('// A preload prepares the *next* player');
      expect(
        marker,
        isNonNegative,
        reason: 'the isPreload branch of loadVideo is the one that streams',
      );
      final body = manager.substring(marker, marker + 1600);
      expect(body, contains('usedStreaming = true;'));
      expect(body, contains('CachedVideoPlayerPlus.networkUrl('));
      expect(body, contains('skipCache: true,'));
      expect(
        body.substring(0, body.indexOf('skipCache: true,')),
        isNot(contains('_downloads.download(')),
        reason: 'a whole-file transfer cannot finish inside a preload timeout',
      );
    });

    // A preloaded stream becomes the active stream the moment the user swipes
    // onto it, without passing through initializeController again -- the
    // orchestrator finds it in the LRU. If the flag did not travel with it,
    // the arbiter would believe the newly active video was playing from cache
    // and release the whole-file warms straight into it.
    test('a preloaded stream is known to be a stream', () {
      final flag = manager.indexOf('isStreaming: usedStreaming');
      expect(flag, isNonNegative);
      final preceding = manager.substring(flag - 700, flag);
      expect(
        preceding,
        isNot(contains('if (!isPreload) {')),
        reason: 'the flag belongs to the transfer, not to who asked for it',
      );
    });

    // Holding *everything* back meant the next player was prepared only once
    // the stream had reported itself healthy -- three smooth 700 ms ticks
    // after the first frame. A feed scrolled at any pace never spends that
    // long on one video, so nothing was ever prepared and every swipe paid a
    // cold start: the "les videos du bas mettent plus de temps" report.
    //
    // The release is now in two stages. The visible video keeps the
    // connection strictly to itself until it renders; from that point the
    // next player may open its stream, while the whole-file warms -- the
    // thing that actually starved a stream in production -- keep waiting for
    // stability.
    test('the next player is released at the first frame, warms at stability',
        () {
      final scheduler = _read('lib/videos/domain/video_preload_scheduler.dart');
      final arbiter = _read('lib/videos/domain/playback_bandwidth_arbiter.dart');
      final player = _read('lib/widgets/smart_video_player.dart');

      expect(scheduler, contains('bool allowFileWarms = true,'));
      expect(scheduler, contains('if (warmFileOnly && !allowFileWarms) {'));

      // Stage one hands the request over once and leaves it held.
      expect(arbiter, contains('DeferredPreloadRequest? takeDeferredPlayers('));
      expect(arbiter, contains('if (request == null || request.playersReleased) return null;'));
      expect(
        arbiter,
        contains('request.playersReleased = true;'),
        reason: 'stage two replays the whole request; the player must not be '
            'asked for twice',
      );

      expect(
        manager,
        contains('void markActivePlaybackStarted(String contextKey, String url) {'),
      );
      final release = manager.indexOf('void _releaseDeferredPlayers(');
      expect(release, isNonNegative);
      final body = manager.substring(release, release + 500);
      expect(body, contains('_bandwidth.takeDeferredPlayers(contextKey)'));
      expect(body, contains('allowFileWarms: false,'));

      // The first frame and the preload request race, and a video promoted
      // from a preload renders before its own preloadSurrounding call is even
      // made. Recording the answer instead of reacting to it is what makes
      // the order irrelevant.
      expect(arbiter, contains('void markRendered(String contextKey, String resolvedUrl)'));
      expect(arbiter, contains('bool hasRendered(String contextKey, String? resolvedUrl)'));
      expect(
        manager,
        contains('if (_bandwidth.hasRendered(contextKey, resolvedActive)) {'),
      );

      // Only the tile the user is on speaks for the context.
      expect(player, contains('void _reportFirstFrameRendered() {'));
      final report = player.indexOf('void _reportFirstFrameRendered() {');
      final reportBody = player.substring(report, report + 420);
      expect(reportBody, contains('if (_reportedFirstFrame) return;'));
      expect(
        reportBody,
        contains('if (_vc.currentIndex.value != widget.currentIndex) return;'),
      );
      expect(
        reportBody,
        contains('_videoManager.markActivePlaybackStarted('),
      );

      // And the flag is per attached player, like the stability one.
      final bind = player.indexOf('void _bindPlayer(');
      expect(bind, isNonNegative);
      expect(
        player.substring(bind, bind + 400),
        contains('_reportedFirstFrame = false;'),
      );
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
