// ignore_for_file: body_might_complete_normally_catch_error

import 'dart:async';
import 'dart:collection';
import 'dart:io' show File;

import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/video_cache_manager.dart' as custom_cache;
import 'package:adfoot/utils/video_source_selector.dart';
import 'package:adfoot/videos/domain/network_profile.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum VideoLoadState { loading, ready, errorTimeout, errorSource }

enum VideoMetricType { initSuccess, initError }

class VideoMetricEvent {
  VideoMetricEvent({
    required this.type,
    required this.url,
    required this.isPreload,
    this.duration,
    this.usedCache,
    this.error,
  });

  final VideoMetricType type;
  final String url;
  final bool isPreload;
  final Duration? duration;
  final bool? usedCache;
  final Object? error;
}

class _VideoNetworkTuning {
  const _VideoNetworkTuning({
    required this.maxActive,
    required this.maxConcurrentInits,
    required this.preloadRadius,
    required this.preloadTimeout,
    required this.activeTimeout,
  });

  final int maxActive;
  final int maxConcurrentInits;
  final int preloadRadius;
  final Duration preloadTimeout;
  final Duration activeTimeout;
}

class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal();

  // ---------------------------------------------------------------------------
  // Core state
  // ---------------------------------------------------------------------------

  final Map<String, LinkedHashMap<String, CachedVideoPlayerPlus>> _lruByContext =
      {};
  final Map<String, Map<String, Future<CachedVideoPlayerPlus>>>
      _initFuturesByContext = {};
  final Map<String, Map<String, VideoLoadState>> _loadStatesByContext = {};

  /// originalUrl -> resolvedUrl
  final Map<String, Map<String, String>> _resolvedUrlByContext = {};

  // ---------------------------------------------------------------------------
  // Network profile
  // ---------------------------------------------------------------------------

  final NetworkProfileService _networkProfileService = NetworkProfileService();

  final ValueNotifier<NetworkProfile?> profileNotifier =
      ValueNotifier<NetworkProfile?>(null);

  NetworkProfile? _networkProfile;
  Future<NetworkProfile>? _networkProfileFuture;

  bool _profilePrefersHls = false;

  int _maxActive = 8;
  int _maxConcurrentInits = 3;
  int _preloadRadius = 1;
  Duration _preloadTimeout = const Duration(seconds: 8);
  Duration _activeTimeout = const Duration(seconds: 12);

  int _activeInits = 0;

  NetworkProfile? get currentProfile => _networkProfile;

  bool get _isHighBandwidth =>
      _networkProfile?.tier == NetworkProfileTier.high;

  void setNetworkProfile(NetworkProfile profile) {
    _applyNetworkProfile(profile);
  }

  Future<void> refreshNetworkProfile() async {
    final profile = await _networkProfileService.detectProfile();
    _applyNetworkProfile(profile);
  }

  Future<void> _ensureNetworkProfile() async {
    if (_networkProfile != null) return;
    _networkProfileFuture ??= _networkProfileService.detectProfile();
    final profile = await _networkProfileFuture!;
    _applyNetworkProfile(profile);
  }

  void _applyNetworkProfile(NetworkProfile profile) {
    _networkProfile = profile;
    profileNotifier.value = profile;

    final tuning = _tuningFor(profile.tier);
    _maxActive = tuning.maxActive;
    _maxConcurrentInits = tuning.maxConcurrentInits;
    _preloadRadius = tuning.preloadRadius;
    _preloadTimeout = tuning.preloadTimeout;
    _activeTimeout = tuning.activeTimeout;

    _profilePrefersHls = profile.preferHls;

    debugPrint(
      "[VideoManager] NetworkProfile applied: $profile → "
      "radius=$_preloadRadius maxActive=$_maxActive concurrent=$_maxConcurrentInits",
    );
  }

  _VideoNetworkTuning _tuningFor(NetworkProfileTier tier) {
    switch (tier) {
      case NetworkProfileTier.high:
        return const _VideoNetworkTuning(
          maxActive: 8,
          maxConcurrentInits: 3,
          preloadRadius: 2,
          preloadTimeout: Duration(seconds: 8),
          activeTimeout: Duration(seconds: 12),
        );
      case NetworkProfileTier.medium:
        return const _VideoNetworkTuning(
          maxActive: 6,
          maxConcurrentInits: 2,
          preloadRadius: 1,
          preloadTimeout: Duration(seconds: 10),
          activeTimeout: Duration(seconds: 12),
        );
      case NetworkProfileTier.low:
        return const _VideoNetworkTuning(
          maxActive: 4,
          maxConcurrentInits: 1,
          preloadRadius: 0,
          preloadTimeout: Duration(seconds: 12),
          activeTimeout: Duration(seconds: 15),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Adaptive sources
  // ---------------------------------------------------------------------------

  bool adaptiveSourcesEnabled = false;

  void updateAdaptiveFlag(bool enabled) {
    adaptiveSourcesEnabled = enabled;
  }

    // ---------------------------------------------------------------------------
  // Metrics (debug / observabilité – sans impact runtime)
  // ---------------------------------------------------------------------------

  void Function(VideoMetricEvent event)? onMetrics;

  int _initCount = 0;
  int _cacheHits = 0;
  int _errorCount = 0;

  String _cacheRateString() {
    if (_initCount == 0) return '0%';
    final rate = (_cacheHits / _initCount) * 100;
    return "${rate.toStringAsFixed(1)}%";
  }

  void _registerMetric(VideoMetricEvent event) {
    switch (event.type) {
      case VideoMetricType.initSuccess:
        _initCount++;
        if (event.usedCache == true) _cacheHits++;
        debugPrint(
          "[VideoManager][metrics] "
          "${event.isPreload ? 'preload' : 'active'} "
          "cache=${event.usedCache} "
          "cacheRate=${_cacheRateString()} "
          "errors=$_errorCount",
        );
        break;

      case VideoMetricType.initError:
        _errorCount++;
        debugPrint(
          "[VideoManager][metrics] error url=${event.url} "
          "cacheRate=${_cacheRateString()} "
          "errors=$_errorCount",
        );
        break;
    }

    final listener = onMetrics;
    if (listener != null) {
      listener(event);
    }
  }


  // ---------------------------------------------------------------------------
  // Connectivity
  // ---------------------------------------------------------------------------

  Future<bool> _hasConnectivity() async {
    try {
      final dynamic res = await Connectivity().checkConnectivity();
      if (res is List<ConnectivityResult>) {
        return res.any((r) => r != ConnectivityResult.none);
      }
      if (res is ConnectivityResult) {
        return res != ConnectivityResult.none;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  // ---------------------------------------------------------------------------
  // URL helpers
  // ---------------------------------------------------------------------------

  String _resolveKey(String contextKey, String originalUrl) =>
      _resolvedUrlByContext[contextKey]?[originalUrl] ?? originalUrl;

  String? getResolvedUrl(String contextKey, String originalUrl) =>
      _resolvedUrlByContext[contextKey]?[originalUrl];

  Iterable<String> _originalUrlsForResolved(
    String contextKey,
    String resolvedUrl,
  ) {
    final mapping = _resolvedUrlByContext[contextKey];
    if (mapping == null) return const [];
    return mapping.entries
        .where((e) => e.value == resolvedUrl)
        .map((e) => e.key);
  }

  // ---------------------------------------------------------------------------
  // Controller initialization (CRITICAL PATH)
  // ---------------------------------------------------------------------------

  Future<CachedVideoPlayerPlus> initializeController(
    String contextKey,
    String url, {
    List<VideoSource> sources = const [],
    bool useHls = false,
    bool isPreload = false,
    bool autoPlay = false,
    String? activeUrl,
  }) async {
    await _ensureNetworkProfile();

    final preferHls = useHls || _profilePrefersHls;

    final candidates = VideoSourceSelector.prioritizedSources(
      fallbackUrl: url,
      sources: sources,
      adaptiveEnabled: adaptiveSourcesEnabled,
      highBandwidth: _isHighBandwidth,
      preferHls: preferHls,
    );

    if (candidates.isEmpty) {
      _loadStatesByContext.putIfAbsent(contextKey, () => {})[url] =
          VideoLoadState.errorSource;
      return Future.error(Exception("Aucune source vidéo disponible"));
    }

    _loadStatesByContext.putIfAbsent(contextKey, () => {})[url] =
        VideoLoadState.loading;
    _lruByContext.putIfAbsent(contextKey, () => LinkedHashMap());
    _initFuturesByContext.putIfAbsent(contextKey, () => {});
    _resolvedUrlByContext.putIfAbsent(contextKey, () => {});

    final lru = _lruByContext[contextKey]!;
    final futures = _initFuturesByContext[contextKey]!;

    bool isHlsSource(VideoSource source) =>
        source.isHls ||
        source.url.toLowerCase().trim().contains('.m3u8');

    Future<CachedVideoPlayerPlus> attempt(VideoSource candidate) async {
      final effectiveUrl = candidate.url;
      final isHls = isHlsSource(candidate);
      final cacheKey = effectiveUrl;

      // 1) LRU hit
      if (lru.containsKey(cacheKey)) {
        final existing = lru.remove(cacheKey)!;
        final v = existing.controller.value;
        if (v.isInitialized && !v.hasError) {
          lru[cacheKey] = existing;
          await _enforceLimit(contextKey, activeUrl: activeUrl);
          _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
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
            lru[cacheKey] = player;
            await _enforceLimit(contextKey, activeUrl: activeUrl);
            _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
            if (autoPlay && !v.isPlaying) {
              await player.controller.play().catchError((_) {});
            }
            return player;
          }
        } catch (_) {}
        futures.remove(cacheKey);
        lru.remove(cacheKey);
      }

      Future<CachedVideoPlayerPlus> loadVideo() async {
        final stopwatch = Stopwatch()..start();
        bool usedCache = false;
        File? file;

        try {
          final timeout = isPreload ? _preloadTimeout : _activeTimeout;
          CachedVideoPlayerPlus player;

          if (kIsWeb || isHls) {
            player = CachedVideoPlayerPlus.networkUrl(
              Uri.parse(effectiveUrl),
            );
          } else {
            file = await custom_cache.VideoCacheManager.getFileIfCached(
              effectiveUrl,
            );
            usedCache = file != null && await file.exists();

            if (file == null || !(await file.exists())) {
              file = await _downloadVideo(effectiveUrl, force: true);
            }

            if (!await file.exists()) {
              throw Exception("Fichier introuvable : $effectiveUrl");
            }

            player = CachedVideoPlayerPlus.file(file);
          }

          await player.initialize().timeout(timeout, onTimeout: () {
            _loadStatesByContext[contextKey]![url] =
                VideoLoadState.errorTimeout;
            throw TimeoutException("Init timeout : $effectiveUrl");
          });

          final v = player.controller.value;
          if (!v.isInitialized || v.hasError) {
            if (!kIsWeb && file != null) {
              unawaited(file.delete().catchError((_) {}));
            }
            throw Exception("Init error : $effectiveUrl");
          }

          player.controller.setLooping(true);

          lru[cacheKey] = player;
          await _enforceLimit(contextKey, activeUrl: activeUrl);

          _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;

          if (autoPlay && !player.controller.value.isPlaying) {
            await player.controller.play().catchError((_) {});
          }

          stopwatch.stop();

          debugPrint(
            "[VideoManager] Init ${isPreload ? 'preload' : 'active'} "
            "${kIsWeb ? 'web' : (usedCache ? 'cache' : 'download')} "
            "in ${stopwatch.elapsedMilliseconds}ms -> $effectiveUrl",
          );

          _registerMetric(
            VideoMetricEvent(
              type: VideoMetricType.initSuccess,
              url: effectiveUrl,
              isPreload: isPreload,
              duration: stopwatch.elapsed,
              usedCache: usedCache,
            ),
          );

          unawaited(_checkCacheSize());
          return player;
        } catch (e, st) {
          debugPrint("❌ Video init error $effectiveUrl: $e\n$st");

          _loadStatesByContext[contextKey]![url] =
              VideoLoadState.errorSource;
          lru.remove(cacheKey);

          _registerMetric(
            VideoMetricEvent(
              type: VideoMetricType.initError,
              url: effectiveUrl,
              isPreload: isPreload,
              error: e,
            ),
          );

          return Future.error(e);
        }
      }

      // 3) Concurrency limit
      while (_activeInits >= _maxConcurrentInits) {
        await Future.delayed(const Duration(milliseconds: 80));
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

    for (final candidate in candidates) {
      final effectiveUrl = candidate.url;
      _resolvedUrlByContext[contextKey]![url] = effectiveUrl;

      try {
        final player = await attempt(candidate);
        _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
        return player;
      } on TimeoutException catch (e) {
        lastErrorState = VideoLoadState.errorTimeout;
        lastError = e;
        _loadStatesByContext[contextKey]![url] = VideoLoadState.loading;
      } catch (e) {
        lastErrorState = VideoLoadState.errorSource;
        lastError = e;
        _loadStatesByContext[contextKey]![url] = VideoLoadState.loading;
      }
    }

    _loadStatesByContext[contextKey]![url] =
        lastErrorState ?? VideoLoadState.errorSource;

    return Future.error(
      lastError ?? Exception("Aucune source vidéo disponible"),
    );
  }

  // ---------------------------------------------------------------------------
  // Download / cache
  // ---------------------------------------------------------------------------

  Future<File> _downloadVideo(String url, {bool force = false}) async {
    final hasNet = await _hasConnectivity();
    if (!hasNet) throw Exception("No internet : $url");

    if (force) {
      final cached =
          await custom_cache.VideoCacheManager.getFileIfCached(url);
      if (cached != null && await cached.exists()) {
        await cached.delete().catchError((_) {});
      }
    }

    final info = await custom_cache.VideoCacheManager
        .getInstance()
        .then((m) => m.downloadFile(url));

    return info.file;
  }

  Future<void> _checkCacheSize() async {
    if (!kIsWeb) {
      final size =
          await custom_cache.VideoCacheManager.getCacheSizeInMB();
      if (size > 300) {
        debugPrint("⚠️ Cache >300MB: ${size}MB");
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LRU enforce
  // ---------------------------------------------------------------------------

  Future<void> _enforceLimit(
    String contextKey, {
    String? activeUrl,
  }) async {
    final lru = _lruByContext[contextKey]!;
    final resolvedActive =
        activeUrl != null ? _resolveKey(contextKey, activeUrl) : null;

    while (lru.length > _maxActive) {
      final oldestKey =
          lru.keys.firstWhere((k) => k != resolvedActive, orElse: () => '');
      if (oldestKey.isEmpty) break;

      final player = lru.remove(oldestKey)!;
      await safePause(player);
      await safeDispose(player);

      _initFuturesByContext[contextKey]?.remove(oldestKey);

      for (final original
          in _originalUrlsForResolved(contextKey, oldestKey)) {
        _loadStatesByContext[contextKey]?.remove(original);
        _resolvedUrlByContext[contextKey]?.remove(original);
      }

      debugPrint("[VideoManager] Disposed LRU controller: $oldestKey");
    }
  }

  // ---------------------------------------------------------------------------
  // Public helpers
  // ---------------------------------------------------------------------------

  Future<void> preloadSurrounding(
    String contextKey,
    List<Video> videos,
    int index, {
    String? activeUrl,
    bool useHls = false,
  }) async {
    await _ensureNetworkProfile();
    final radius = _preloadRadius;
    if (radius <= 0) return;

    for (int i = 1; i <= radius; i++) {
      if (index - i >= 0) {
        final v = videos[index - i];
        unawaited(
          initializeController(
            contextKey,
            v.videoUrl,
            sources: v.sources,
            useHls: useHls && v.hasHlsSource,
            isPreload: true,
            activeUrl: activeUrl,
          ),
        );
      }
      if (index + i < videos.length) {
        final v = videos[index + i];
        unawaited(
          initializeController(
            contextKey,
            v.videoUrl,
            sources: v.sources,
            useHls: useHls && v.hasHlsSource,
            isPreload: true,
            activeUrl: activeUrl,
          ),
        );
      }
    }
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
      _loadStatesByContext[contextKey]?[url];

  Future<void> pauseAllExcept(String contextKey, String? keepUrl) async {
    final lru = _lruByContext[contextKey] ?? {};
    final resolvedKeep =
        keepUrl != null ? _resolveKey(contextKey, keepUrl) : null;

    for (final entry in lru.entries.toList()) {
      if (entry.key != resolvedKeep &&
          entry.value.controller.value.isInitialized) {
        await safePause(entry.value);
      }
    }
  }

  Future<void> pauseAll(String contextKey) async {
    final lru = _lruByContext[contextKey] ?? {};
    for (final player in lru.values) {
      await safePause(player);
    }
  }

  Future<void> disposeAllForContext(String contextKey) async {
    final lru = _lruByContext.remove(contextKey);
    if (lru != null) {
      for (final player in lru.values) {
        await safePause(player);
        await safeDispose(player);
      }
    }
    _initFuturesByContext.remove(contextKey);
    _loadStatesByContext.remove(contextKey);
    _resolvedUrlByContext.remove(contextKey);
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
      _loadStatesByContext[contextKey]?.remove(url);
      _resolvedUrlByContext[contextKey]?.remove(url);
    }
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
