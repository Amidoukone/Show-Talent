// ignore_for_file: body_might_complete_normally_catch_error

import 'dart:async';
import 'dart:collection';
import 'dart:io' show File;

import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/video_cache_manager.dart' as custom_cache;
import 'package:adfoot/utils/video_source_selector.dart';
import 'package:adfoot/videos/data/video_download_service.dart';
import 'package:adfoot/videos/domain/network_profile.dart';
import 'package:adfoot/videos/domain/playback_bandwidth_arbiter.dart';
import 'package:adfoot/videos/domain/video_network_tuning.dart';
import 'package:adfoot/videos/domain/video_playback_metrics.dart';
import 'package:adfoot/videos/domain/video_preload_scheduler.dart';
import 'package:adfoot/videos/domain/video_ui_signals.dart';

// VideoLoadState moved to video_ui_signals.dart with the rest of the state
// the UI reads. Re-exported so the twenty call sites that ask VideoManager
// for it keep working.
export 'package:adfoot/videos/domain/video_playback_metrics.dart'
    show VideoMetricEvent, VideoMetricType;
export 'package:adfoot/videos/domain/video_ui_signals.dart'
    show VideoLoadState;
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:adfoot/services/app_logger.dart';

class _VideoInitCancelled implements Exception {
  const _VideoInitCancelled(this.reason);

  final String reason;

  @override
  String toString() => 'Video init cancelled: $reason';
}

class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal();

  static const Duration _activeAdaptiveSelectionBudget = Duration(
    milliseconds: 450,
  );

  /// How long an init may wait for a concurrency slot before going anyway.
  ///
  /// [_maxConcurrentInits] is a tuning knob (1 on a low-tier network), not a
  /// correctness constraint, but the wait for it was an unbounded loop. A slot
  /// is released by `whenComplete`, so it is held for as long as `loadVideo()`
  /// runs — and that path can include a `downloadFile` on a video of up to
  /// 150 MB through `flutter_cache_manager`'s `HttpFileService`, which sets no
  /// socket deadline of its own. One connection that stalls without closing
  /// therefore pinned the only slot, and every later init in the app —
  /// active playback included — waited behind it forever. The feed simply
  /// stopped loading, showing a spinner with no error, until the app was
  /// killed.
  ///
  /// Briefly running one init over the limit is a far smaller cost than that,
  /// so the wait expires and proceeds.
  static const Duration _initSlotWaitTimeout = Duration(seconds: 20);
  static const Duration _initSlotPollInterval = Duration(milliseconds: 80);
  /// Getting bytes onto disk, and keeping the disk cache in budget.
  ///
  /// A URL goes in and a file comes out; nothing here knows about players or
  /// contexts, which is why it was the first thing to come out of this class.
  final VideoDownloadService _downloads = VideoDownloadService();

  // ---------------------------------------------------------------------------
  // Core state
  // ---------------------------------------------------------------------------

  final Map<String, LinkedHashMap<String, CachedVideoPlayerPlus>>
  _lruByContext = {};
  final Map<String, Map<String, Future<CachedVideoPlayerPlus>>>
  _initFuturesByContext = {};

  /// Who gets the connection: the video on screen, or its neighbours.
  final PlaybackBandwidthArbiter _bandwidth = PlaybackBandwidthArbiter();

  /// Which neighbours to warm, in what order, and how far apart.
  late final VideoPreloadScheduler _preloads = VideoPreloadScheduler(
    preload: (contextKey, video, {activeUrl, required warmFileOnly}) {
      if (warmFileOnly) {
        return warmVideoFile(video);
      }
      return initializeController(
        contextKey,
        video.videoUrl,
        sources: video.sources,
        isPreload: true,
        activeUrl: activeUrl,
      );
    },
  );

  /// Puts a video's bytes on disk without opening a player for it.
  ///
  /// A cached file still makes the next swipe fast — the controller opens
  /// from local storage instead of the network — but it costs no decoder,
  /// which is the resource the device actually runs out of.
  Future<void> warmVideoFile(Video video) async {
    if (kIsWeb) return;

    final source = VideoSourceSelector.preferredSource(
      fallbackUrl: video.videoUrl,
      sources: video.sources,
      adaptiveEnabled: adaptiveSourcesEnabled,
      highBandwidth: _isHighBandwidth,
    );
    final url = source?.url ?? video.videoUrl;
    if (url.isEmpty) return;

    final cached = await custom_cache.VideoCacheManager.getFileIfCached(url);
    if (cached != null && await cached.exists()) return;

    await _downloads.download(url);
  }


  // ---------------------------------------------------------------------------
  // Network profile
  // ---------------------------------------------------------------------------

  /// Detecting the connection's tier, and what that tier costs.
  final VideoNetworkTuningController _network = VideoNetworkTuningController();

  ValueNotifier<NetworkProfile?> get profileNotifier => _network.profileNotifier;

  /// Load states, resolved renditions, and the notifiers widgets rebuild on.
  final VideoUiSignals _ui = VideoUiSignals();

  ValueNotifier<int> get uiRevision => _ui.revision;

  /// App-wide ceiling on initialised native players.
  ///
  /// An initialised `CachedVideoPlayerPlus` holds a MediaCodec instance for as
  /// long as it lives, and mid-range Android devices run out of them well
  /// before a Dart list would notice. adfoot-production, 2026-08-22 at 09:19:
  ///
  ///     MediaCodecVideoRenderer error ... format_supported=YES
  ///     ... [1920, 1080, 25.0, ...]
  ///
  /// The device could decode that format -- it says so -- it had simply run
  /// out of instances to decode it with, in a `profile:<uid>` context opened
  /// on top of a `home` context that was still holding its own.
  ///
  /// Four, not eight. Eight was chosen to match the largest per-context
  /// budget so a single feed would never be constrained -- which turned out
  /// to be the wrong instinct entirely: on 2026-08-23 the same error appeared
  /// again on a *preload*, with the budget in place and only the home feed
  /// open. The ceiling has to sit where the hardware sits, not where the
  /// software would like it to.
  ///
  /// Now that a preload past the nearest neighbour warms the file without
  /// opening a player, a feed needs two: the video being watched and the one
  /// after it. Four leaves room for a second context -- a profile pushed over
  /// the feed -- and nothing more.
  static const int _globalMaxActive = 4;

  int _activeInits = 0;

  NetworkProfile? get currentProfile => _network.profile;

  bool get _isHighBandwidth => _network.isHighBandwidth;

  // The tuning table is the tier's consequence, so it is read from the tier,
  // never cached here: a stale copy would keep asking for the heaviest
  // rendition after the connection had been re-measured as slow.
  int get _maxActive => _network.tuning.maxActive;
  int get _maxConcurrentInits => _network.tuning.maxConcurrentInits;
  int get _preloadRadius => _network.tuning.preloadRadius;
  Duration get _preloadTimeout => _network.tuning.preloadTimeout;
  Duration get _activeTimeout => _network.tuning.activeTimeout;

  void _setLoadState(String contextKey, String url, VideoLoadState state) =>
      _ui.setLoadState(contextKey, url, state);

  void _setResolvedUrl(
    String contextKey,
    String originalUrl,
    String resolvedUrl,
  ) => _ui.setResolvedUrl(contextKey, originalUrl, resolvedUrl);

  void _removeUiTracking(String contextKey, String url) =>
      _ui.forget(contextKey, url);

  bool _isContextActive(
    String contextKey,
    LinkedHashMap<String, CachedVideoPlayerPlus> lru,
    Map<String, Future<CachedVideoPlayerPlus>> futures,
  ) {
    return identical(_lruByContext[contextKey], lru) &&
        identical(_initFuturesByContext[contextKey], futures);
  }

  // ---------------------------------------------------------------------------
  // Streaming bandwidth arbitration
  // ---------------------------------------------------------------------------

  void _markStreaming(
    String contextKey,
    String resolvedUrl, {
    required bool isStreaming,
  }) {
    _bandwidth.markStreaming(
      contextKey,
      resolvedUrl,
      isStreaming: isStreaming,
    );
  }

  bool _isStreamingUrl(String contextKey, String? resolvedUrl) =>
      _bandwidth.isStreamingUrl(contextKey, resolvedUrl);

  /// Reports that the visible video has been playing smoothly long enough for
  /// background downloads to be safe again.
  ///
  /// The stream keeps the connection to itself until this arrives, so the
  /// clip the user is actually watching gets the bandwidth first. Called by
  /// SmartVideoPlayer's stall watchdog once playback has advanced over
  /// several consecutive ticks without buffering.
  void markActivePlaybackStable(String contextKey, String url) {
    final resolved = _resolveKey(contextKey, url);
    _markStreaming(contextKey, resolved, isStreaming: false);
    _flushDeferredPreload(contextKey);
  }

  void _flushDeferredPreload(String contextKey) {
    final pending = _bandwidth.takeDeferred(contextKey);
    if (pending == null) return;

    unawaited(
      preloadSurrounding(
        contextKey,
        pending.videos,
        pending.index,
        activeUrl: pending.activeUrl,
        preferForward: pending.preferForward,
      ),
    );
  }

  @visibleForTesting
  bool isStreamingUrlForTests(String contextKey, String resolvedUrl) =>
      _isStreamingUrl(contextKey, resolvedUrl);

  @visibleForTesting
  void markStreamingForTests(
    String contextKey,
    String resolvedUrl, {
    required bool isStreaming,
  }) {
    _markStreaming(contextKey, resolvedUrl, isStreaming: isStreaming);
  }

  @visibleForTesting
  bool hasDeferredPreloadForTests(String contextKey) =>
      _bandwidth.hasDeferred(contextKey);

  void setNetworkProfile(NetworkProfile profile) => _network.override(profile);

  Future<void> warmNetworkProfile() => _network.warm();

  Future<void> refreshNetworkProfile() => _network.refresh();

  @visibleForTesting
  void resetNetworkProfileStateForTests({
    NetworkProfileService? networkProfileService,
    NetworkProfile profile = VideoNetworkTuningController.bootstrapProfile,
  }) {
    adaptiveSourcesEnabled = false;
    _ui.resetCounters();
    _network.resetForTests(service: networkProfileService, profile: profile);
  }

  @visibleForTesting
  void resetCacheSizeThrottleForTests({
    Future<int> Function()? cacheSizeProvider,
    DateTime Function()? nowProvider,
  }) {
    _downloads.configureCacheSizeProbe(
      cacheSizeProvider: cacheSizeProvider,
      nowProvider: nowProvider,
    );
  }

  @visibleForTesting
  Future<void> checkCacheSizeForTests({bool force = false}) {
    return _downloads.checkCacheSizeThrottled(force: force);
  }

  @visibleForTesting
  Future<void> enforceLimitForTests(String contextKey, {String? activeUrl}) {
    return _enforceLimit(contextKey, activeUrl: activeUrl);
  }

  // ---------------------------------------------------------------------------
  // Adaptive sources
  // ---------------------------------------------------------------------------

  bool adaptiveSourcesEnabled = false;

  void updateAdaptiveFlag(bool enabled) {
    adaptiveSourcesEnabled = enabled;
  }

  bool _shouldAwaitAdaptiveProfileSelection({
    required bool isPreload,
    required List<VideoSource> sources,
  }) {
    if (isPreload || !adaptiveSourcesEnabled || _network.isInitialized) {
      return false;
    }

    final mp4SourceCount = sources.where((source) => source.isMp4).length;
    return mp4SourceCount > 1;
  }

  // ---------------------------------------------------------------------------
  // Metrics (debug / observabilité – sans impact runtime)
  // ---------------------------------------------------------------------------

  final VideoPlaybackMetricsRecorder _metrics = VideoPlaybackMetricsRecorder();

  /// Installed by `VideoMetricsObserver`.
  set onMetrics(void Function(VideoMetricEvent event)? listener) =>
      _metrics.onMetrics = listener;

  void Function(VideoMetricEvent event)? get onMetrics => _metrics.onMetrics;

  void _registerMetric(VideoMetricEvent event) => _metrics.record(event);

  // ---------------------------------------------------------------------------
  // Connectivity
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // URL helpers
  // ---------------------------------------------------------------------------

  String _resolveKey(String contextKey, String originalUrl) =>
      _ui.resolveKey(contextKey, originalUrl);

  String? getResolvedUrl(String contextKey, String originalUrl) =>
      _ui.resolvedUrl(contextKey, originalUrl);

  List<String> _originalUrlsForResolved(String contextKey, String resolved) =>
      _ui.originalUrlsFor(contextKey, resolved);

  @visibleForTesting
  void seedResolvedUrlForTests(
    String contextKey,
    String originalUrl,
    String resolvedUrl,
  ) {
    _setResolvedUrl(contextKey, originalUrl, resolvedUrl);
  }

  @visibleForTesting
  void purgeResolvedUiTrackingForTests(String contextKey, String resolvedUrl) {
    for (final original in _originalUrlsForResolved(contextKey, resolvedUrl)) {
      _removeUiTracking(contextKey, original);
    }
  }

  bool _shouldPromotePreferredSource({
    required VideoSource currentSource,
    required VideoSource preferredSource,
  }) {
    final currentHeight = currentSource.height ?? 0;
    final preferredHeight = preferredSource.height ?? 0;
    if (currentHeight > 0 && preferredHeight > 0) {
      return preferredHeight > currentHeight;
    }

    final currentBitrate = currentSource.bitrate ?? 0;
    final preferredBitrate = preferredSource.bitrate ?? 0;
    if (currentBitrate > 0 && preferredBitrate > 0) {
      return preferredBitrate > currentBitrate;
    }

    return false;
  }

  bool shouldReuseControllerForRequest({
    required String originalUrl,
    String? resolvedUrl,
    List<VideoSource> sources = const [],
    required bool isPreload,
  }) {
    if (isPreload || !adaptiveSourcesEnabled || sources.isEmpty) {
      return true;
    }

    final effectiveResolvedUrl = resolvedUrl?.trim();
    if (effectiveResolvedUrl == null || effectiveResolvedUrl.isEmpty) {
      return true;
    }

    final preferredSource = VideoSourceSelector.preferredSource(
      fallbackUrl: originalUrl,
      sources: sources,
      adaptiveEnabled: adaptiveSourcesEnabled,
      highBandwidth: _isHighBandwidth,
    );
    if (preferredSource == null || preferredSource.url.isEmpty) {
      return true;
    }

    if (preferredSource.url == effectiveResolvedUrl) {
      return true;
    }

    final currentSource = VideoSourceSelector.sourceForUrl(
      url: effectiveResolvedUrl,
      sources: sources,
    );
    if (currentSource == null) {
      AppLogger.debug(
        '[VideoManager] Refreshing active controller for $originalUrl '
        'because $effectiveResolvedUrl is outside the current playback contract '
        '(preferred=${preferredSource.url})',
      );
      return false;
    }

    final shouldPromote = _shouldPromotePreferredSource(
      currentSource: currentSource,
      preferredSource: preferredSource,
    );
    if (shouldPromote) {
      AppLogger.debug(
        '[VideoManager] Refreshing active controller for $originalUrl '
        'to promote ${currentSource.quality ?? currentSource.height ?? 'current'} '
        '-> ${preferredSource.quality ?? preferredSource.height ?? 'preferred'}',
      );
      return false;
    }

    return true;
  }

  String _playbackBranch({
    required bool usedCache,
    required bool usedStreaming,
    required bool usedStreamFallback,
  }) {
    if (usedStreamFallback) {
      return 'mp4_stream_fallback';
    }
    if (usedCache) {
      return 'mp4_cache';
    }
    if (usedStreaming) {
      return 'mp4_stream';
    }
    return 'mp4_download';
  }

  bool _shouldForceFreshDownloadAfterPrimaryInitFailure({
    required bool usedStreaming,
    required bool isPreload,
    required String url,
  }) {
    return !usedStreaming && !isPreload && VideoDownloadService.isFirebaseStorageUrl(url);
  }

  /// Always false: a stream gets the connection to itself.
  ///
  /// Reported from production: a freshly published video -- the only one in
  /// no cache at all -- paused and resumed continuously for its whole
  /// duration, on the tile and again after scrolling away and back, while
  /// every already-cached video played normally. No recovery ran and nothing
  /// was logged, because nothing failed: the player was simply starved by
  /// concurrent downloads of the file it was trying to stream.
  ///
  /// One of those downloads was the player's own: left at its default,
  /// `CachedVideoPlayerPlus.networkUrl(...).initialize()` fires an unawaited
  /// `downloadFile` of the whole video whenever the URL is missing from *its*
  /// private cache, then streams the same URL anyway. That one is gone --
  /// the streaming branch now passes `skipCache: true`. Warming the cache
  /// here would simply put it back under a different name.
  ///
  /// The active video reaches the cache the same way every other video does:
  /// as somebody's neighbour, through the preload path, once the stream has
  /// reported itself healthy (see [markActivePlaybackStable]).
  ///
  /// Kept as a method rather than deleted so the decision stays visible at the
  /// call site, and so the guardrail can pin it.
  bool _shouldWarmCacheAfterStreamInit({
    required bool isPreload,
    required bool usedStreaming,
    required bool usedStreamFallback,
  }) {
    return false;
  }

  @visibleForTesting
  bool shouldForceFreshDownloadAfterPrimaryInitFailureForTests({
    required bool usedStreaming,
    required bool isPreload,
    required String url,
  }) {
    return _shouldForceFreshDownloadAfterPrimaryInitFailure(
      usedStreaming: usedStreaming,
      isPreload: isPreload,
      url: url,
    );
  }

  @visibleForTesting
  bool shouldWarmCacheAfterStreamInitForTests({
    required bool isPreload,
    required bool usedStreaming,
    required bool usedStreamFallback,
  }) {
    return _shouldWarmCacheAfterStreamInit(
      isPreload: isPreload,
      usedStreaming: usedStreaming,
      usedStreamFallback: usedStreamFallback,
    );
  }

  // ---------------------------------------------------------------------------
  // Controller initialization (CRITICAL PATH)
  // ---------------------------------------------------------------------------

  Future<CachedVideoPlayerPlus> initializeController(
    String contextKey,
    String url, {
    List<VideoSource> sources = const [],
    bool preferDownloadedFile = false,
    bool isPreload = false,
    bool autoPlay = false,
    String? activeUrl,
    String? recoveryFallbackFromSourceType,
    String? recoveryReason,
  }) async {
    _network.ensureWarm();

    if (_shouldAwaitAdaptiveProfileSelection(
      isPreload: isPreload,
      sources: sources,
    )) {
      await _network.awaitDetection(_activeAdaptiveSelectionBudget);
    }

    final candidates = VideoSourceSelector.prioritizedSources(
      fallbackUrl: url,
      sources: sources,
      adaptiveEnabled: adaptiveSourcesEnabled,
      highBandwidth: _isHighBandwidth,
    );

    if (candidates.isEmpty) {
      _setLoadState(contextKey, url, VideoLoadState.errorSource);
      return Future.error(Exception("Aucune source vidéo disponible"));
    }

    _setLoadState(contextKey, url, VideoLoadState.loading);
    _lruByContext.putIfAbsent(contextKey, () => LinkedHashMap());
    _initFuturesByContext.putIfAbsent(contextKey, () => {});
    _ui.ensureContext(contextKey);

    final lru = _lruByContext[contextKey]!;
    final futures = _initFuturesByContext[contextKey]!;

    String sourceTypeFor(VideoSource source) {
      final type = source.type?.toLowerCase().trim();
      return type == null || type.isEmpty ? 'mp4' : type;
    }

    Future<CachedVideoPlayerPlus> attempt(
      VideoSource candidate, {
      String? fallbackFromSourceType,
    }) async {
      final effectiveUrl = candidate.url;
      final sourceType = sourceTypeFor(candidate);
      final cacheKey = effectiveUrl;

      // 1) LRU hit
      if (lru.containsKey(cacheKey)) {
        final existing = lru.remove(cacheKey)!;
        final v = existing.controller.value;
        if (v.isInitialized && !v.hasError) {
          // disposeAllForContext removes the contextKey's map entries but
          // doesn't invalidate a map object a concurrent attempt() already
          // captured -- without this check, a context torn down mid-flight
          // could hand back an already-disposed controller here (dispose()
          // doesn't flip isInitialized/hasError). Same guard as the slow
          // path below.
          if (!_isContextActive(contextKey, lru, futures)) {
            throw const _VideoInitCancelled('context_disposed_lru_hit');
          }
          lru[cacheKey] = existing;
          await _enforceLimit(contextKey, activeUrl: activeUrl);
          _setLoadState(contextKey, url, VideoLoadState.ready);
          if (autoPlay && !v.isPlaying) {
            await existing.controller.play().catchError((_) {});
          }
          return existing;
        }
        await safeDispose(existing);
        lru.remove(cacheKey);
      }

      // 2) Future en cours
      if (futures.containsKey(cacheKey)) {
        try {
          final player = await futures[cacheKey]!;
          final v = player.controller.value;
          if (v.isInitialized && !v.hasError) {
            if (!_isContextActive(contextKey, lru, futures)) {
              throw const _VideoInitCancelled('context_disposed_future_hit');
            }
            lru[cacheKey] = player;
            await _enforceLimit(contextKey, activeUrl: activeUrl);
            _setLoadState(contextKey, url, VideoLoadState.ready);
            if (autoPlay && !v.isPlaying) {
              await player.controller.play().catchError((_) {});
            }
            return player;
          }
        } catch (error) {
          if (error is _VideoInitCancelled) rethrow;
        }
        futures.remove(cacheKey);
        lru.remove(cacheKey);
      }

      Future<CachedVideoPlayerPlus> loadVideo() async {
        final stopwatch = Stopwatch()..start();
        bool usedCache = false;
        bool usedStreaming = false;
        bool usedStreamFallback = false;
        bool fallbackCacheHit = false;
        bool reusedInFlightDownload = false;
        File? file;
        Duration? primaryInitDuration;
        Duration? fallbackDownloadDuration;
        Duration? fallbackInitDuration;

        try {
          final timeout = isPreload ? _preloadTimeout : _activeTimeout;
          CachedVideoPlayerPlus player;

          if (kIsWeb) {
            player = CachedVideoPlayerPlus.networkUrl(Uri.parse(effectiveUrl));
          } else {
            file = await custom_cache.VideoCacheManager.getFileIfCached(
              effectiveUrl,
            );
            usedCache = file != null && await file.exists();

            if (usedCache && await file.exists()) {
              player = CachedVideoPlayerPlus.file(file);
            } else if (!isPreload) {
              if (preferDownloadedFile) {
                // On recovery after a stalled MP4 stream, prefer a local file
                // so we do not restart the same fragile network path again.
                final downloadResult = await _downloads.download(effectiveUrl);
                file = downloadResult.file;
                if (!await file.exists()) {
                  throw Exception("Fichier introuvable : $effectiveUrl");
                }
                player = CachedVideoPlayerPlus.file(file);
              } else {
                // Active playback: start immediately on the network stream.
                //
                // `skipCache: true` is the whole point. Left at its default,
                // CachedVideoPlayerPlus fires an unawaited downloadFile of the
                // *same* URL into its own private cache the moment it finds no
                // entry there, then streams that URL for playback. Two
                // transfers of identical bytes, and the one the user is
                // watching loses the race -- which is exactly the "pause /
                // reprise" loop reported on every freshly published video.
                //
                // That private cache is also invisible to VideoCacheManager,
                // so it was never purged and quietly held a second copy of
                // every video ever streamed. This app owns its cache: the
                // preload path fills it, VideoCacheManager purges it.
                usedStreaming = true;
                player = CachedVideoPlayerPlus.networkUrl(
                  Uri.parse(effectiveUrl),
                  skipCache: true,
                );
              }
            } else {
              final downloadResult = await _downloads.download(
                effectiveUrl,
                force: true,
              );
              file = downloadResult.file;
              if (!await file.exists()) {
                throw Exception("Fichier introuvable : $effectiveUrl");
              }
              player = CachedVideoPlayerPlus.file(file);
            }
          }

          Future<void> initializePlayer(
            CachedVideoPlayerPlus target, {
            required String stage,
          }) async {
            await target.initialize().timeout(
              timeout,
              onTimeout: () {
                _setLoadState(contextKey, url, VideoLoadState.errorTimeout);
                throw TimeoutException("Init timeout ($stage) : $effectiveUrl");
              },
            );

            final v = target.controller.value;
            if (!v.isInitialized || v.hasError) {
              throw Exception("Init error ($stage) : $effectiveUrl");
            }
          }

          try {
            final primaryInitStopwatch = Stopwatch()..start();
            try {
              await initializePlayer(
                player,
                stage: usedStreaming ? "stream" : "initial",
              );
            } finally {
              primaryInitStopwatch.stop();
              primaryInitDuration = primaryInitStopwatch.elapsed;
            }
          } catch (streamError) {
            final canFallbackToDownloaded =
                !kIsWeb && !isPreload && VideoDownloadService.isFirebaseStorageUrl(effectiveUrl);
            if (!canFallbackToDownloaded) {
              rethrow;
            }

            AppLogger.debug(
              "[VideoManager] Primary init failed, trying local fallback -> "
              "$effectiveUrl ($streamError)",
            );

            await safeDispose(player);

            final shouldForceFreshDownload =
                _shouldForceFreshDownloadAfterPrimaryInitFailure(
                  usedStreaming: usedStreaming,
                  isPreload: isPreload,
                  url: effectiveUrl,
                );
            if (shouldForceFreshDownload) {
              if (file != null) {
                await VideoDownloadService.safeDeleteFile(file);
              }
              await custom_cache.VideoCacheManager.removeCachedFile(
                effectiveUrl,
              );
              file = null;
              fallbackCacheHit = false;
            } else {
              file = await custom_cache.VideoCacheManager.getFileIfCached(
                effectiveUrl,
              );
              fallbackCacheHit = file != null && await file.exists();
            }

            if (!fallbackCacheHit) {
              final downloadResult = await _downloads.download(
                effectiveUrl,
                force: shouldForceFreshDownload,
              );
              file = downloadResult.file;
              fallbackDownloadDuration = downloadResult.duration;
              reusedInFlightDownload = downloadResult.reusedInFlight;
            } else {
              fallbackDownloadDuration = Duration.zero;
            }

            final fallbackFile = file;
            if (fallbackFile == null || !await fallbackFile.exists()) {
              throw Exception("Fallback file introuvable : $effectiveUrl");
            }

            player = CachedVideoPlayerPlus.file(fallbackFile);
            usedStreaming = false;
            usedCache = true;
            usedStreamFallback = true;

            final fallbackInitStopwatch = Stopwatch()..start();
            await initializePlayer(player, stage: "stream-fallback");
            fallbackInitStopwatch.stop();
            fallbackInitDuration = fallbackInitStopwatch.elapsed;
          }

          player.controller.setLooping(true);

          if (!_isContextActive(contextKey, lru, futures)) {
            await safeDispose(player);
            throw const _VideoInitCancelled('context_disposed_before_attach');
          }

          lru[cacheKey] = player;
          await _enforceLimit(contextKey, activeUrl: activeUrl);

          if (!_isContextActive(contextKey, lru, futures)) {
            lru.remove(cacheKey);
            await safeDispose(player);
            throw const _VideoInitCancelled('context_disposed_after_attach');
          }

          _setLoadState(contextKey, url, VideoLoadState.ready);

          if (!isPreload) {
            // A preload is never a stream, and it deliberately skips the
            // active URL, so only the active init can speak for it here.
            _markStreaming(
              contextKey,
              cacheKey,
              isStreaming: usedStreaming,
            );
            if (!usedStreaming) {
              _flushDeferredPreload(contextKey);
            }
          }

          if (autoPlay && !player.controller.value.isPlaying) {
            await player.controller.play().catchError((_) {});
          }

          stopwatch.stop();

          AppLogger.debug(
            "[VideoManager] Init ${isPreload ? 'preload' : 'active'} "
            "${kIsWeb ? 'web' : _playbackBranch(usedCache: usedCache, usedStreaming: usedStreaming, usedStreamFallback: usedStreamFallback)} "
            "in ${stopwatch.elapsedMilliseconds}ms -> $effectiveUrl "
            "(recovery=$recoveryReason primary=${primaryInitDuration?.inMilliseconds} "
            "fallbackDownload=${fallbackDownloadDuration?.inMilliseconds} "
            "fallbackInit=${fallbackInitDuration?.inMilliseconds} "
            "fallbackCacheHit=$fallbackCacheHit reuseDownload=$reusedInFlightDownload)",
          );

          _registerMetric(
            VideoMetricEvent(
              type: VideoMetricType.initSuccess,
              url: effectiveUrl,
              isPreload: isPreload,
              contextKey: contextKey,
              duration: stopwatch.elapsed,
              usedCache: usedCache,
              sourceType: sourceType,
              sourceQuality: candidate.quality,
              sourceHeight: candidate.height,
              sourceBitrate: candidate.bitrate,
              playbackBranch: _playbackBranch(
                usedCache: usedCache,
                usedStreaming: usedStreaming,
                usedStreamFallback: usedStreamFallback,
              ),
              usedStreaming: usedStreaming,
              usedStreamFallback: usedStreamFallback,
              fallbackFromSourceType: fallbackFromSourceType,
              recoveryReason: recoveryReason,
              primaryInitDuration: primaryInitDuration,
              fallbackDownloadDuration: fallbackDownloadDuration,
              fallbackInitDuration: fallbackInitDuration,
              fallbackCacheHit: usedStreamFallback ? fallbackCacheHit : null,
              reusedInFlightDownload: usedStreamFallback
                  ? reusedInFlightDownload
                  : null,
            ),
          );

          if (_shouldWarmCacheAfterStreamInit(
            isPreload: isPreload,
            usedStreaming: usedStreaming,
            usedStreamFallback: usedStreamFallback,
          )) {
            unawaited(_downloads.warmCacheAfterPlaybackStabilizes(effectiveUrl));
          }

          unawaited(_downloads.checkCacheSizeThrottled());
          return player;
        } catch (e, st) {
          // Whatever happens next, nothing is streaming this URL any more:
          // leaving the mark set would suppress this context's preloads for
          // good.
          _markStreaming(contextKey, cacheKey, isStreaming: false);

          if (e is _VideoInitCancelled) {
            lru.remove(cacheKey);
            return Future.error(e);
          }
          AppLogger.debug("❌ Video init error $effectiveUrl: $e\n$st");

          if (!kIsWeb && file != null) {
            unawaited(VideoDownloadService.safeDeleteFile(file));
          }

          _setLoadState(contextKey, url, VideoLoadState.errorSource);
          lru.remove(cacheKey);

          _registerMetric(
            VideoMetricEvent(
              type: VideoMetricType.initError,
              url: effectiveUrl,
              isPreload: isPreload,
              contextKey: contextKey,
              error: e,
              sourceType: sourceType,
              sourceQuality: candidate.quality,
              sourceHeight: candidate.height,
              sourceBitrate: candidate.bitrate,
              playbackBranch: _playbackBranch(
                usedCache: usedCache,
                usedStreaming: usedStreaming,
                usedStreamFallback: usedStreamFallback,
              ),
              recoveryReason: recoveryReason,
              primaryInitDuration: primaryInitDuration,
              fallbackDownloadDuration: fallbackDownloadDuration,
              fallbackInitDuration: fallbackInitDuration,
              fallbackCacheHit: usedStreamFallback ? fallbackCacheHit : null,
              reusedInFlightDownload: usedStreamFallback
                  ? reusedInFlightDownload
                  : null,
            ),
          );

          return Future.error(e);
        }
      }

      // 3) Concurrency limit — bounded, and abandoned if the context goes
      // away while we are queued (nobody is left to watch the result).
      final slotDeadline = DateTime.now().add(_initSlotWaitTimeout);
      while (_activeInits >= _maxConcurrentInits) {
        if (!_isContextActive(contextKey, lru, futures)) {
          throw const _VideoInitCancelled('context_disposed_waiting_for_slot');
        }
        if (!DateTime.now().isBefore(slotDeadline)) {
          AppLogger.debug(
            '[VideoManager] Init slot wait expired after '
            '${_initSlotWaitTimeout.inSeconds}s (active=$_activeInits, '
            'max=$_maxConcurrentInits); proceeding anyway -> $effectiveUrl',
          );
          break;
        }
        await Future.delayed(_initSlotPollInterval);
      }

      _activeInits++;
      final future = loadVideo().whenComplete(() => _activeInits--);
      futures[cacheKey] = future;

      try {
        final result = await future;
        futures.remove(cacheKey);
        return result;
      } catch (e) {
        futures.remove(cacheKey);
        lru.remove(cacheKey);
        rethrow;
      }
    }

    VideoLoadState? lastErrorState;
    Object? lastError;
    String? fallbackFromSourceType = recoveryFallbackFromSourceType;

    for (final candidate in candidates) {
      final effectiveUrl = candidate.url;
      _setResolvedUrl(contextKey, url, effectiveUrl);

      try {
        final player = await attempt(
          candidate,
          fallbackFromSourceType: fallbackFromSourceType,
        );
        _setLoadState(contextKey, url, VideoLoadState.ready);
        return player;
      } on _VideoInitCancelled {
        return Future.error(const _VideoInitCancelled('context_disposed'));
      } on TimeoutException catch (e) {
        lastErrorState = VideoLoadState.errorTimeout;
        lastError = e;
        fallbackFromSourceType ??= sourceTypeFor(candidate);
        _setLoadState(contextKey, url, VideoLoadState.loading);
      } catch (e) {
        lastErrorState = VideoLoadState.errorSource;
        lastError = e;
        fallbackFromSourceType ??= sourceTypeFor(candidate);
        _setLoadState(contextKey, url, VideoLoadState.loading);
      }
    }

    _setLoadState(
      contextKey,
      url,
      lastErrorState ?? VideoLoadState.errorSource,
    );

    return Future.error(
      lastError ?? Exception("Aucune source vidéo disponible"),
    );
  }

  // ---------------------------------------------------------------------------
  // Download / cache
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // LRU enforce
  // ---------------------------------------------------------------------------

  Future<void> _enforceLimit(String contextKey, {String? activeUrl}) async {
    final lru = _lruByContext[contextKey];
    if (lru == null) return;
    final resolvedActive = activeUrl != null
        ? _resolveKey(contextKey, activeUrl)
        : null;

    while (lru.length > _maxActive) {
      final oldestKey = lru.keys.firstWhere(
        (k) => k != resolvedActive,
        orElse: () => '',
      );
      if (oldestKey.isEmpty) break;
      if (!await _releaseController(contextKey, oldestKey)) break;
    }

    await _enforceGlobalLimit(contextKey, resolvedActive);
  }

  /// Total initialised native players, across every context.
  int get _totalActiveControllers =>
      _lruByContext.values.fold(0, (sum, lru) => sum + lru.length);

  /// Brings the whole app back under [_globalMaxActive].
  ///
  /// [_maxActive] is a *per-context* budget, and contexts are not exclusive:
  /// pushing a publisher's profile over the feed leaves `home` holding all of
  /// its controllers while `profile:<uid>` starts building its own. Two
  /// budgets, one pool of hardware decoders -- and that pool is neither per
  /// context nor per app.
  ///
  /// A context nobody is looking at gives its decoders back first, oldest use
  /// first, because it is only holding them on the chance the user comes back
  /// to it. Coming back costs a local file open: the neighbours are already on
  /// disk, put there by the preload path.
  Future<void> _enforceGlobalLimit(
    String focusedContextKey,
    String? keepResolvedUrl,
  ) async {
    if (_totalActiveControllers <= _globalMaxActive) return;

    final orderedContexts = <String>[
      ..._lruByContext.keys.where((key) => key != focusedContextKey),
      focusedContextKey,
    ];

    for (final contextKey in orderedContexts) {
      final lru = _lruByContext[contextKey];
      if (lru == null || lru.isEmpty) continue;

      while (_totalActiveControllers > _globalMaxActive && lru.isNotEmpty) {
        final isFocused = contextKey == focusedContextKey;
        final oldestKey = lru.keys.firstWhere(
          (key) => !(isFocused && key == keepResolvedUrl),
          orElse: () => '',
        );
        if (oldestKey.isEmpty) break;
        if (!await _releaseController(contextKey, oldestKey)) break;

        AppLogger.debug(
          '[VideoManager] Released $oldestKey from $contextKey for the '
          'app-wide decoder budget (focused=$focusedContextKey)',
        );
      }
    }
  }

  /// Disposes one controller and forgets everything that pointed at it.
  ///
  /// Returns false when there was nothing to release, so the callers' loops
  /// cannot spin.
  Future<bool> _releaseController(String contextKey, String resolvedKey) async {
    final player = _lruByContext[contextKey]?.remove(resolvedKey);
    if (player == null) return false;

    await safePause(player);
    await safeDispose(player);

    _initFuturesByContext[contextKey]?.remove(resolvedKey);
    _markStreaming(contextKey, resolvedKey, isStreaming: false);

    for (final original in _originalUrlsForResolved(contextKey, resolvedKey)) {
      _removeUiTracking(contextKey, original);
    }

    AppLogger.debug("[VideoManager] Disposed LRU controller: $resolvedKey");
    return true;
  }

  // ---------------------------------------------------------------------------
  // Public helpers
  // ---------------------------------------------------------------------------

  Future<void> preloadSurrounding(
    String contextKey,
    List<Video> videos,
    int index, {
    String? activeUrl,
    bool preferForward = true,
  }) async {
    _network.ensureWarm();
    final radius = _preloadRadius;
    if (radius <= 0) return;

    // Hold the neighbours back while the visible video is still pulling its
    // own bytes off the network. Each preload downloads a whole file, so
    // firing two or three of them alongside a live stream is what turned a
    // freshly published video into a pause/resume loop for its entire
    // duration. The request is replayed as soon as the stream reports itself
    // healthy (markActivePlaybackStable) or the active video switches to a
    // cached file -- so a normal network still preloads exactly as before,
    // only a couple of seconds later.
    final resolvedActive = activeUrl == null || activeUrl.trim().isEmpty
        ? null
        : _resolveKey(contextKey, activeUrl);
    if (_isStreamingUrl(contextKey, resolvedActive)) {
      _bandwidth.defer(
        contextKey,
        DeferredPreloadRequest(
          videos: videos,
          index: index,
          preferForward: preferForward,
          activeUrl: activeUrl,
        ),
      );
      return;
    }
    _bandwidth.clearDeferred(contextKey);

    _preloads.scheduleAround(
      contextKey: contextKey,
      videos: videos,
      index: index,
      radius: radius,
      activeUrl: activeUrl,
      preferForward: preferForward,
    );
  }

  @visibleForTesting
  Duration preloadPositionDelayForTests(int preloadPosition) =>
      _preloads.delayForPosition(preloadPosition);

  @visibleForTesting
  List<int> preloadOrderForTests({
    required int totalVideos,
    required int index,
    required int radius,
    bool preferForward = true,
  }) {
    return _preloads.orderAround(
      totalVideos: totalVideos,
      index: index,
      radius: radius,
      preferForward: preferForward,
    );
  }

  CachedVideoPlayerPlus? getController(String contextKey, String url) {
    final resolved = _resolveKey(contextKey, url);
    final player = _lruByContext[contextKey]?[resolved];
    if (player == null) return null;
    try {
      final v = player.controller.value;
      if (!v.isInitialized || v.hasError) return null;
      return player;
    } catch (_) {
      return null;
    }
  }

  VideoLoadState? getLoadState(String contextKey, String url) =>
      _ui.loadState(contextKey, url);

  ValueListenable<int> watchVideoUi(String contextKey, String url) =>
      _ui.watch(contextKey, url);

  void unwatchVideoUi(String contextKey, String url) =>
      _ui.unwatch(contextKey, url);

  List<String> activeOriginalUrlsForContext(String contextKey) {
    final lru = _lruByContext[contextKey];
    if (lru == null || lru.isEmpty) return const [];
    return _ui.originalUrlsAmong(contextKey, lru.keys.toSet());
  }

  Future<void> pauseAllExcept(String contextKey, String? keepUrl) async {
    final lru = _lruByContext[contextKey] ?? {};
    final resolvedKeep = keepUrl != null
        ? _resolveKey(contextKey, keepUrl)
        : null;

    final pauses = <Future<void>>[];
    for (final entry in lru.entries.toList()) {
      if (entry.key == resolvedKeep) continue;
      // Pausing a controller ends whatever it was pulling off the network, so
      // it no longer competes with anything. Leaving the mark set kept a video
      // the user had already scrolled past counted as an active stream, and
      // this runs on every index change -- the exact moment the previous
      // video stops being one.
      _markStreaming(contextKey, entry.key, isStreaming: false);
      bool isInitialized = false;
      try {
        isInitialized = entry.value.controller.value.isInitialized;
      } catch (_) {
        isInitialized = false;
      }
      if (isInitialized) {
        // Collected rather than awaited in place: every page change waits on
        // this before the next video may start, and the pauses are
        // independent of one another.
        pauses.add(safePause(entry.value));
      }
    }

    if (pauses.isNotEmpty) {
      await Future.wait(pauses);
    }
  }

  /// Pauses every controller this context currently holds.
  ///
  /// The snapshot is not a nicety. Iterating `lru.values` directly means
  /// holding a live view of the map across an `await`, and this map is
  /// written from four other places while that await is suspended:
  /// `attempt()` inserts on success and removes on failure, `_enforceLimit`
  /// evicts, `disposeUrls` removes. adfoot-production logged the collision
  /// twice on 2026-08-22 alone —
  /// `Concurrent modification during iteration: _Map len:4` at
  /// `VideoManager.pauseAll` — and because the throw escapes an unawaited
  /// call it lands in `runZonedGuarded`, which books it in Crashlytics as a
  /// **fatal** crash of an app that had merely paused a video.
  ///
  /// The pauses also run together rather than one after another: this sits on
  /// the critical path of every page change, and eight sequential round trips
  /// to the platform channel are eight frames the next video does not get.
  Future<void> pauseAll(String contextKey) async {
    final players = _lruByContext[contextKey]?.values.toList(growable: false);
    if (players == null || players.isEmpty) return;
    await Future.wait(players.map(safePause));
  }

  /// Frees every native player this context holds except the one on screen.
  ///
  /// An initialised `CachedVideoPlayerPlus` holds a MediaCodec instance for
  /// as long as it lives, and pausing it does not give that back — only
  /// disposing does. Contexts are independent (`home`, `profile:<uid>`), each
  /// with its own [_maxActive] budget, and a context is *not* torn down when
  /// a route is pushed on top of it. Opening a publisher's profile from the
  /// feed therefore stacks a second budget on the first, on a device whose
  /// decoder count is neither per-context nor per-app.
  ///
  /// adfoot-production, 2026-08-22 at 09:19, in `profile:zDuzNuDD…`:
  ///
  ///     MediaCodecVideoRenderer error … format_supported=YES
  ///     … [1920, 1080, 25.0, …]
  ///
  /// The device could decode that format perfectly well — it says so — it had
  /// simply run out of instances to decode it with. The session ended on the
  /// error overlay, and the user's answer was the retry button, eighteen
  /// times across the logged window.
  ///
  /// The controller left alive is the one being watched, so coming back to
  /// this feed resumes instantly. Its neighbours return through the preload
  /// path from the disk cache they already filled, which is a local file
  /// open, not a download.
  Future<void> releaseControllersExcept(
    String contextKey,
    String? keepUrl,
  ) async {
    final lru = _lruByContext[contextKey];
    if (lru == null || lru.isEmpty) return;

    final trimmedKeep = keepUrl?.trim();
    final resolvedKeep = trimmedKeep == null || trimmedKeep.isEmpty
        ? null
        : _resolveKey(contextKey, trimmedKeep);

    final doomed = lru.keys
        .where((key) => key != resolvedKeep)
        .toList(growable: false);
    if (doomed.isEmpty) return;

    await Future.wait(
      doomed.map((key) async {
        final player = lru.remove(key);
        if (player == null) return;
        await safePause(player);
        await safeDispose(player);
      }),
    );

    for (final key in doomed) {
      _initFuturesByContext[contextKey]?.remove(key);
      _markStreaming(contextKey, key, isStreaming: false);
      for (final original in _originalUrlsForResolved(contextKey, key)) {
        _removeUiTracking(contextKey, original);
      }
    }

    AppLogger.debug(
      '[VideoManager] Released ${doomed.length} controller(s) in $contextKey, '
      'kept ${resolvedKeep ?? 'none'}',
    );
  }

  Future<void> disposeAllForContext(String contextKey) async {
    final lru = _lruByContext.remove(contextKey);
    if (lru != null) {
      // Detaching the map from _lruByContext stops new controllers being
      // added (attempt() re-checks _isContextActive before it inserts), but
      // an in-flight attempt that already captured this same map still
      // *removes* from it on failure. Iterating it live across the awaits
      // below is the same concurrent-modification hazard pauseAll was
      // crashing on, so take the snapshot here too, and tear the controllers
      // down together instead of one round trip at a time.
      final players = lru.values.toList(growable: false);
      lru.clear();
      await Future.wait(
        players.map((player) async {
          await safePause(player);
          await safeDispose(player);
        }),
      );
    }
    _initFuturesByContext.remove(contextKey);
    _ui.forgetContext(contextKey);
    _preloads.forgetContext(contextKey);
    _bandwidth.forgetContext(contextKey);
  }

  Future<void> disposeUrls(String contextKey, List<String> urls) async {
    final lru = _lruByContext[contextKey];
    if (lru == null) return;

    for (final url in urls) {
      final resolved = _resolveKey(contextKey, url);
      final player = lru.remove(resolved);

      if (player != null) {
        await safePause(player);
        await safeDispose(player);
      }

      _initFuturesByContext[contextKey]?.remove(resolved);
      _markStreaming(contextKey, resolved, isStreaming: false);
      _removeUiTracking(contextKey, url);
    }

    _flushDeferredPreload(contextKey);
  }

  Future<void> safePause(CachedVideoPlayerPlus player) async {
    try {
      final c = player.controller;
      if (c.value.isInitialized && c.value.isPlaying) {
        await c.pause();
      }
    } catch (_) {}
  }

  Future<void> safeDispose(CachedVideoPlayerPlus player) async {
    try {
      await player.dispose();
    } catch (_) {}
  }

  Future<void> waitUntilInitialized(String contextKey, String url) async {
    final resolved = _resolveKey(contextKey, url);
    final player = _lruByContext[contextKey]?[resolved];
    if (player == null || player.controller.value.isInitialized) return;

    final c = player.controller;
    final completer = Completer<void>();

    void listener() {
      if (c.value.isInitialized) {
        c.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      }
    }

    c.addListener(listener);
    try {
      await completer.future.timeout(_activeTimeout);
    } catch (_) {
      c.removeListener(listener);
    }
  }
}
