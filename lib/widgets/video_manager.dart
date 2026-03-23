// ignore_for_file: body_might_complete_normally_catch_error

import 'dart:async';
import 'dart:collection';
import 'dart:io' show File, HandshakeException, HttpException, SocketException;
import 'dart:math' show Random;

import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/video_cache_manager.dart' as custom_cache;
import 'package:adfoot/utils/video_source_selector.dart';
import 'package:adfoot/videos/domain/network_profile.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show HttpExceptionWithStatus;
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart' show VideoFormat;

enum VideoLoadState { loading, ready, errorTimeout, errorSource }

enum VideoMetricType { initSuccess, initError }

class VideoMetricEvent {
  VideoMetricEvent({
    required this.type,
    required this.url,
    required this.isPreload,
    this.contextKey,
    this.duration,
    this.usedCache,
    this.error,
    this.initCount,
    this.cacheHits,
    this.errorCount,
    this.cacheHitRate,
    this.sourceType,
    this.sourceQuality,
    this.sourceHeight,
    this.sourceBitrate,
    this.requestedHls,
    this.cacheBypassed,
    this.playbackBranch,
    this.hlsSuppressedReason,
    this.manifestHost,
    this.manifestPath,
    this.manifestHasToken,
    this.usedStreaming,
    this.usedStreamFallback,
    this.fallbackFromSourceType,
    this.recoveryReason,
    this.primaryInitDuration,
    this.fallbackDownloadDuration,
    this.fallbackInitDuration,
    this.fallbackCacheHit,
    this.reusedInFlightDownload,
  });

  final VideoMetricType type;
  final String url;
  final bool isPreload;
  final String? contextKey;
  final Duration? duration;
  final bool? usedCache;
  final Object? error;
  final int? initCount;
  final int? cacheHits;
  final int? errorCount;
  final double? cacheHitRate;
  final String? sourceType;
  final String? sourceQuality;
  final int? sourceHeight;
  final int? sourceBitrate;
  final bool? requestedHls;
  final bool? cacheBypassed;
  final String? playbackBranch;
  final String? hlsSuppressedReason;
  final String? manifestHost;
  final String? manifestPath;
  final bool? manifestHasToken;
  final bool? usedStreaming;
  final bool? usedStreamFallback;
  final String? fallbackFromSourceType;
  final String? recoveryReason;
  final Duration? primaryInitDuration;
  final Duration? fallbackDownloadDuration;
  final Duration? fallbackInitDuration;
  final bool? fallbackCacheHit;
  final bool? reusedInFlightDownload;

  VideoMetricEvent copyWith({
    int? initCount,
    int? cacheHits,
    int? errorCount,
    double? cacheHitRate,
  }) {
    return VideoMetricEvent(
      type: type,
      url: url,
      isPreload: isPreload,
      contextKey: contextKey,
      duration: duration,
      usedCache: usedCache,
      error: error,
      initCount: initCount ?? this.initCount,
      cacheHits: cacheHits ?? this.cacheHits,
      errorCount: errorCount ?? this.errorCount,
      cacheHitRate: cacheHitRate ?? this.cacheHitRate,
      sourceType: sourceType,
      sourceQuality: sourceQuality,
      sourceHeight: sourceHeight,
      sourceBitrate: sourceBitrate,
      requestedHls: requestedHls,
      cacheBypassed: cacheBypassed,
      playbackBranch: playbackBranch,
      hlsSuppressedReason: hlsSuppressedReason,
      manifestHost: manifestHost,
      manifestPath: manifestPath,
      manifestHasToken: manifestHasToken,
      usedStreaming: usedStreaming,
      usedStreamFallback: usedStreamFallback,
      fallbackFromSourceType: fallbackFromSourceType,
      recoveryReason: recoveryReason,
      primaryInitDuration: primaryInitDuration,
      fallbackDownloadDuration: fallbackDownloadDuration,
      fallbackInitDuration: fallbackInitDuration,
      fallbackCacheHit: fallbackCacheHit,
      reusedInFlightDownload: reusedInFlightDownload,
    );
  }
}

class _HlsBranchDetails {
  const _HlsBranchDetails({
    required this.host,
    required this.path,
    required this.hasToken,
  });

  final String? host;
  final String? path;
  final bool hasToken;
}

class _VideoDownloadResult {
  const _VideoDownloadResult({
    required this.file,
    required this.duration,
    required this.reusedInFlight,
  });

  final File file;
  final Duration duration;
  final bool reusedInFlight;
}

class _VideoInitCancelled implements Exception {
  const _VideoInitCancelled(this.reason);

  final String reason;

  @override
  String toString() => 'Video init cancelled: $reason';
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

class _VideoUiWatchEntry {
  _VideoUiWatchEntry() : notifier = ValueNotifier<int>(0);

  final ValueNotifier<int> notifier;
  int watcherCount = 0;
}

class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal() {
    _applyNetworkProfile(
      _bootstrapNetworkProfile,
      reason: 'bootstrap',
      markInitialized: false,
    );
  }

  static const String _firebaseStorageHost = 'firebasestorage.googleapis.com';
  static const int _firebaseDownloadMaxAttempts = 4;
  static const Duration _firebaseRetryBaseDelay = Duration(milliseconds: 350);
  static const Duration _firebaseRetryMaxDelay = Duration(seconds: 3);
  static const Duration _cacheSizeCheckThrottle = Duration(minutes: 5);
  static const Duration _activeAdaptiveSelectionBudget =
      Duration(milliseconds: 450);
  static const Duration _postInitStreamCacheWarmupDelay = Duration(seconds: 2);
  static const NetworkProfile _bootstrapNetworkProfile = NetworkProfile(
    tier: NetworkProfileTier.medium,
    hasConnection: true,
    preferHls: false,
  );
  final Random _retryRandom = Random();
  Future<int> Function() _cacheSizeProvider =
      custom_cache.VideoCacheManager.getCacheSizeInMB;
  DateTime Function() _nowProvider = DateTime.now;

  // ---------------------------------------------------------------------------
  // Core state
  // ---------------------------------------------------------------------------

  final Map<String, LinkedHashMap<String, CachedVideoPlayerPlus>>
      _lruByContext = {};
  final Map<String, Map<String, Future<CachedVideoPlayerPlus>>>
      _initFuturesByContext = {};
  final Map<String, Map<String, VideoLoadState>> _loadStatesByContext = {};
  final Map<String, Future<_VideoDownloadResult>> _downloadFuturesByUrl = {};

  /// originalUrl -> resolvedUrl
  final Map<String, Map<String, String>> _resolvedUrlByContext = {};
  final Set<String> _purgedHlsCacheUrls = <String>{};

  // ---------------------------------------------------------------------------
  // Network profile
  // ---------------------------------------------------------------------------

  NetworkProfileService _networkProfileService = NetworkProfileService();

  final ValueNotifier<NetworkProfile?> profileNotifier =
      ValueNotifier<NetworkProfile?>(null);
  final ValueNotifier<int> uiRevision = ValueNotifier<int>(0);
  final Map<String, Map<String, _VideoUiWatchEntry>> _uiWatchersByContext = {};

  NetworkProfile? _networkProfile;
  Future<NetworkProfile>? _networkProfileFuture;
  int _networkProfileRequestToken = 0;
  bool _networkProfileInitialized = false;

  bool _profilePrefersHls = false;

  int _maxActive = 8;
  int _maxConcurrentInits = 3;
  int _preloadRadius = 1;
  Duration _preloadTimeout = const Duration(seconds: 8);
  Duration _activeTimeout = const Duration(seconds: 12);

  int _activeInits = 0;
  DateTime? _lastCacheSizeCheckAt;
  Future<void>? _cacheSizeCheckFuture;

  NetworkProfile? get currentProfile => _networkProfile;

  bool get _isHighBandwidth => _networkProfile?.tier == NetworkProfileTier.high;

  void _bumpRevision(ValueNotifier<int> notifier) {
    final next = notifier.value + 1;
    notifier.value = next > 1000000 ? 0 : next;
  }

  void _notifyUiStateChanged({
    String? contextKey,
    String? url,
  }) {
    _bumpRevision(uiRevision);

    if (contextKey == null || url == null) {
      return;
    }

    final entry = _uiWatchersByContext[contextKey]?[url];
    if (entry == null) {
      return;
    }

    _bumpRevision(entry.notifier);
  }

  void _setLoadState(String contextKey, String url, VideoLoadState state) {
    _loadStatesByContext.putIfAbsent(contextKey, () => {})[url] = state;
    _notifyUiStateChanged(contextKey: contextKey, url: url);
  }

  void _setResolvedUrl(
      String contextKey, String originalUrl, String resolvedUrl) {
    _resolvedUrlByContext.putIfAbsent(contextKey, () => {})[originalUrl] =
        resolvedUrl;
    _notifyUiStateChanged(contextKey: contextKey, url: originalUrl);
  }

  void _removeUiTracking(String contextKey, String url) {
    _loadStatesByContext[contextKey]?.remove(url);
    _resolvedUrlByContext[contextKey]?.remove(url);
    _notifyUiStateChanged(contextKey: contextKey, url: url);
  }

  bool _isContextActive(
    String contextKey,
    LinkedHashMap<String, CachedVideoPlayerPlus> lru,
    Map<String, Future<CachedVideoPlayerPlus>> futures,
  ) {
    return identical(_lruByContext[contextKey], lru) &&
        identical(_initFuturesByContext[contextKey], futures);
  }

  void setNetworkProfile(NetworkProfile profile) {
    _networkProfileRequestToken++;
    _networkProfileFuture = null;
    _applyNetworkProfile(profile, reason: 'override');
  }

  Future<void> warmNetworkProfile() async {
    try {
      await _scheduleNetworkProfileRefresh();
    } catch (_) {}
  }

  Future<void> refreshNetworkProfile() async {
    try {
      await _scheduleNetworkProfileRefresh(force: true);
    } catch (_) {}
  }

  Future<NetworkProfile> _scheduleNetworkProfileRefresh({
    bool force = false,
  }) {
    if (!force && _networkProfileFuture != null) {
      return _networkProfileFuture!;
    }

    final requestToken = ++_networkProfileRequestToken;
    final future = _networkProfileService.detectProfile();
    _networkProfileFuture = future;

    future.then((profile) {
      if (!identical(_networkProfileFuture, future) ||
          _networkProfileRequestToken != requestToken) {
        return;
      }
      _networkProfileFuture = null;
      _applyNetworkProfile(profile, reason: 'detected');
    }).catchError((error, stackTrace) {
      if (!identical(_networkProfileFuture, future) ||
          _networkProfileRequestToken != requestToken) {
        return;
      }
      _networkProfileFuture = null;
      debugPrint('[VideoManager] Network profile refresh failed: $error');
    });

    return future;
  }

  void _ensureNetworkProfileWarm() {
    unawaited(_scheduleNetworkProfileRefresh());
  }

  @visibleForTesting
  void resetNetworkProfileStateForTests({
    NetworkProfileService? networkProfileService,
    NetworkProfile profile = _bootstrapNetworkProfile,
  }) {
    _networkProfileService = networkProfileService ?? NetworkProfileService();
    _networkProfileFuture = null;
    _networkProfileRequestToken = 0;
    adaptiveSourcesEnabled = false;
    hlsStrategyEnabled = false;
    _purgedHlsCacheUrls.clear();
    uiRevision.value = 0;
    for (final byUrl in _uiWatchersByContext.values) {
      for (final entry in byUrl.values) {
        entry.notifier.value = 0;
      }
    }
    _applyNetworkProfile(profile, reason: 'test-reset');
  }

  @visibleForTesting
  void resetCacheSizeThrottleForTests({
    Future<int> Function()? cacheSizeProvider,
    DateTime Function()? nowProvider,
  }) {
    _cacheSizeProvider =
        cacheSizeProvider ?? custom_cache.VideoCacheManager.getCacheSizeInMB;
    _nowProvider = nowProvider ?? DateTime.now;
    _lastCacheSizeCheckAt = null;
    _cacheSizeCheckFuture = null;
  }

  @visibleForTesting
  Future<void> checkCacheSizeForTests({bool force = false}) {
    return _checkCacheSizeThrottled(force: force);
  }

  @visibleForTesting
  Future<void> enforceLimitForTests(String contextKey, {String? activeUrl}) {
    return _enforceLimit(contextKey, activeUrl: activeUrl);
  }

  void _applyNetworkProfile(
    NetworkProfile profile, {
    String reason = 'manual',
    bool markInitialized = true,
  }) {
    _networkProfile = profile;
    _networkProfileInitialized = markInitialized;
    profileNotifier.value = profile;

    final tuning = _tuningFor(profile.tier);
    _maxActive = tuning.maxActive;
    _maxConcurrentInits = tuning.maxConcurrentInits;
    _preloadRadius = tuning.preloadRadius;
    _preloadTimeout = tuning.preloadTimeout;
    _activeTimeout = tuning.activeTimeout;

    _profilePrefersHls = profile.preferHls;

    debugPrint(
      "[VideoManager] NetworkProfile applied ($reason): $profile -> "
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

  Future<void> _checkCacheSizeThrottled({bool force = false}) async {
    final inFlight = _cacheSizeCheckFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final now = _nowProvider();
    final lastCheckAt = _lastCacheSizeCheckAt;
    if (!force &&
        lastCheckAt != null &&
        now.difference(lastCheckAt) < _cacheSizeCheckThrottle) {
      return;
    }

    _lastCacheSizeCheckAt = now;
    final future = _readAndReportCacheSize();
    _cacheSizeCheckFuture = future;

    try {
      await future;
    } finally {
      if (identical(_cacheSizeCheckFuture, future)) {
        _cacheSizeCheckFuture = null;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Adaptive sources
  // ---------------------------------------------------------------------------

  bool adaptiveSourcesEnabled = false;
  bool hlsStrategyEnabled = false;

  void updateAdaptiveFlag(bool enabled) {
    adaptiveSourcesEnabled = enabled;
  }

  void updateHlsStrategyFlag(bool enabled) {
    hlsStrategyEnabled = enabled;
  }

  bool _shouldAwaitAdaptiveProfileSelection({
    required bool isPreload,
    required List<VideoSource> sources,
  }) {
    if (isPreload || !adaptiveSourcesEnabled || _networkProfileInitialized) {
      return false;
    }

    final mp4SourceCount = sources.where((source) => !source.isHls).length;
    return mp4SourceCount > 1;
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
          "source=${event.sourceType} "
          "cache=${event.usedCache} "
          "cacheRate=${_cacheRateString()} "
          "errors=$_errorCount",
        );
        break;

      case VideoMetricType.initError:
        _errorCount++;
        debugPrint(
          "[VideoManager][metrics] error source=${event.sourceType} "
          "url=${event.url} "
          "cacheRate=${_cacheRateString()} "
          "errors=$_errorCount",
        );
        break;
    }

    final cacheHitRate = _initCount == 0 ? 0.0 : _cacheHits / _initCount;
    final enrichedEvent = event.copyWith(
      initCount: _initCount,
      cacheHits: _cacheHits,
      errorCount: _errorCount,
      cacheHitRate: cacheHitRate,
    );

    final listener = onMetrics;
    if (listener != null) {
      listener(enrichedEvent);
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

  List<String> _originalUrlsForResolved(
    String contextKey,
    String resolvedUrl,
  ) {
    final mapping = _resolvedUrlByContext[contextKey];
    if (mapping == null) return const [];
    return mapping.entries
        .where((e) => e.value == resolvedUrl)
        .map((e) => e.key)
        .toList(growable: false);
  }

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

  @visibleForTesting
  bool shouldAttemptHlsForRequest({
    required bool preferHls,
    required bool isPreload,
    TargetPlatform? platform,
  }) {
    return false;
  }

  bool _shouldPromotePreferredSource({
    required VideoSource currentSource,
    required VideoSource preferredSource,
  }) {
    if (preferredSource.isHls != currentSource.isHls) {
      return preferredSource.isHls && !currentSource.isHls;
    }

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
    required bool requestedHls,
    required bool isPreload,
  }) {
    if (isPreload || !adaptiveSourcesEnabled || sources.isEmpty) {
      return true;
    }

    final effectiveResolvedUrl = resolvedUrl?.trim();
    if (effectiveResolvedUrl == null || effectiveResolvedUrl.isEmpty) {
      return true;
    }

    final attemptHls = shouldAttemptHlsForRequest(
      preferHls: requestedHls,
      isPreload: isPreload,
    );
    final preferredSource = VideoSourceSelector.preferredSource(
      fallbackUrl: originalUrl,
      sources: sources,
      adaptiveEnabled: adaptiveSourcesEnabled,
      highBandwidth: _isHighBandwidth,
      preferHls: attemptHls,
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
      debugPrint(
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
      debugPrint(
        '[VideoManager] Refreshing active controller for $originalUrl '
        'to promote ${currentSource.quality ?? currentSource.height ?? 'current'} '
        '-> ${preferredSource.quality ?? preferredSource.height ?? 'preferred'}',
      );
      return false;
    }

    return true;
  }

  String? _hlsSuppressedReason({
    required bool requestedHls,
    required bool attemptedHls,
    required bool isPreload,
  }) {
    if (!requestedHls || attemptedHls) {
      return null;
    }
    return 'mp4_only_baseline';
  }

  _HlsBranchDetails _describeHlsUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return _HlsBranchDetails(
        host: uri.host.isEmpty ? null : uri.host,
        path: uri.path.isEmpty ? null : uri.path,
        hasToken: uri.queryParameters.containsKey('token'),
      );
    } catch (_) {
      return const _HlsBranchDetails(
        host: null,
        path: null,
        hasToken: false,
      );
    }
  }

  String _playbackBranch({
    required bool isHls,
    required bool usedCache,
    required bool usedStreaming,
    required bool usedStreamFallback,
  }) {
    if (isHls) {
      return 'hls_network_direct';
    }
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
    required bool isHls,
    required String url,
  }) {
    return !usedStreaming && !isPreload && !isHls && _isFirebaseStorageUrl(url);
  }

  bool _shouldWarmCacheAfterStreamInit({
    required bool isHls,
    required bool isPreload,
    required bool usedStreaming,
    required bool usedStreamFallback,
  }) {
    return !isHls && !isPreload && usedStreaming && !usedStreamFallback;
  }

  @visibleForTesting
  bool shouldForceFreshDownloadAfterPrimaryInitFailureForTests({
    required bool usedStreaming,
    required bool isPreload,
    required bool isHls,
    required String url,
  }) {
    return _shouldForceFreshDownloadAfterPrimaryInitFailure(
      usedStreaming: usedStreaming,
      isPreload: isPreload,
      isHls: isHls,
      url: url,
    );
  }

  @visibleForTesting
  bool shouldWarmCacheAfterStreamInitForTests({
    required bool isHls,
    required bool isPreload,
    required bool usedStreaming,
    required bool usedStreamFallback,
  }) {
    return _shouldWarmCacheAfterStreamInit(
      isHls: isHls,
      isPreload: isPreload,
      usedStreaming: usedStreaming,
      usedStreamFallback: usedStreamFallback,
    );
  }

  Future<void> _purgeHlsCacheArtifactsIfNeeded(String url) async {
    if (!_purgedHlsCacheUrls.add(url)) {
      return;
    }

    try {
      await CachedVideoPlayerPlus.removeFileFromCache(Uri.parse(url));
    } catch (e) {
      debugPrint(
        '[VideoManager][HLS] cached_video_player cache purge failed for $url: $e',
      );
    }

    await custom_cache.VideoCacheManager.removeCachedFile(url);
  }

  // ---------------------------------------------------------------------------
  // Controller initialization (CRITICAL PATH)
  // ---------------------------------------------------------------------------

  Future<CachedVideoPlayerPlus> initializeController(
    String contextKey,
    String url, {
    List<VideoSource> sources = const [],
    bool useHls = false,
    bool forceMp4Fallback = false,
    bool preferDownloadedFile = false,
    bool isPreload = false,
    bool autoPlay = false,
    String? activeUrl,
    String? recoveryFallbackFromSourceType,
    String? recoveryReason,
  }) async {
    _ensureNetworkProfileWarm();

    if (_shouldAwaitAdaptiveProfileSelection(
      isPreload: isPreload,
      sources: sources,
    )) {
      try {
        await _scheduleNetworkProfileRefresh().timeout(
          _activeAdaptiveSelectionBudget,
        );
      } catch (_) {}
    }

    final requestedHls = !forceMp4Fallback &&
        hlsStrategyEnabled &&
        (useHls || _profilePrefersHls);
    final attemptHls = shouldAttemptHlsForRequest(
      preferHls: requestedHls,
      isPreload: isPreload,
    );
    final hlsSuppressedReason = _hlsSuppressedReason(
      requestedHls: requestedHls,
      attemptedHls: attemptHls,
      isPreload: isPreload,
    );

    final candidates = VideoSourceSelector.prioritizedSources(
      fallbackUrl: url,
      sources: sources,
      adaptiveEnabled: adaptiveSourcesEnabled,
      highBandwidth: _isHighBandwidth,
      preferHls: attemptHls,
    );

    if (hlsSuppressedReason != null) {
      debugPrint(
        '[VideoManager][HLS] Suppressed HLS request for '
        '${isPreload ? 'preload' : 'active'} init -> '
        '$url (reason=$hlsSuppressedReason)',
      );
    }

    if (candidates.isEmpty) {
      _setLoadState(contextKey, url, VideoLoadState.errorSource);
      return Future.error(Exception("Aucune source vidéo disponible"));
    }

    _setLoadState(contextKey, url, VideoLoadState.loading);
    _lruByContext.putIfAbsent(contextKey, () => LinkedHashMap());
    _initFuturesByContext.putIfAbsent(contextKey, () => {});
    _resolvedUrlByContext.putIfAbsent(contextKey, () => {});

    final lru = _lruByContext[contextKey]!;
    final futures = _initFuturesByContext[contextKey]!;

    bool isHlsSource(VideoSource source) =>
        source.isHls || source.url.toLowerCase().trim().contains('.m3u8');

    String sourceTypeFor(VideoSource source) {
      if (isHlsSource(source)) {
        return 'hls';
      }
      final type = source.type?.toLowerCase().trim();
      return type == null || type.isEmpty ? 'mp4' : type;
    }

    Future<CachedVideoPlayerPlus> attempt(
      VideoSource candidate, {
      String? fallbackFromSourceType,
    }) async {
      final effectiveUrl = candidate.url;
      final isHls = isHlsSource(candidate);
      final sourceType = sourceTypeFor(candidate);
      final cacheKey = effectiveUrl;
      final hlsDetails = isHls ? _describeHlsUrl(effectiveUrl) : null;

      // 1) LRU hit
      if (lru.containsKey(cacheKey)) {
        final existing = lru.remove(cacheKey)!;
        final v = existing.controller.value;
        if (v.isInitialized && !v.hasError) {
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
            lru[cacheKey] = player;
            await _enforceLimit(contextKey, activeUrl: activeUrl);
            _setLoadState(contextKey, url, VideoLoadState.ready);
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

          if (kIsWeb || isHls) {
            if (!kIsWeb && isHls) {
              await _purgeHlsCacheArtifactsIfNeeded(effectiveUrl);
              debugPrint(
                '[VideoManager][HLS] '
                '${isPreload ? 'preload' : 'active'} '
                'direct network init -> $effectiveUrl '
                '(cacheBypassed=true host=${hlsDetails?.host} '
                'path=${hlsDetails?.path} token=${hlsDetails?.hasToken})',
              );
            }
            player = CachedVideoPlayerPlus.networkUrl(
              Uri.parse(effectiveUrl),
              formatHint: isHls ? VideoFormat.hls : null,
              skipCache: isHls,
            );
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
                final downloadResult = await _downloadVideo(effectiveUrl);
                file = downloadResult.file;
                if (!await file.exists()) {
                  throw Exception("Fichier introuvable : $effectiveUrl");
                }
                player = CachedVideoPlayerPlus.file(file);
              } else {
                // Active playback: start immediately on network stream,
                // then warm the cache after startup has stabilized.
                usedStreaming = true;
                player = CachedVideoPlayerPlus.networkUrl(
                  Uri.parse(effectiveUrl),
                );
              }
            } else {
              final downloadResult = await _downloadVideo(
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
            await target.initialize().timeout(timeout, onTimeout: () {
              _setLoadState(contextKey, url, VideoLoadState.errorTimeout);
              throw TimeoutException("Init timeout ($stage) : $effectiveUrl");
            });

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
            final isM3u8 = effectiveUrl.toLowerCase().contains('.m3u8');
            final canFallbackToDownloaded = !kIsWeb &&
                !isPreload &&
                _isFirebaseStorageUrl(effectiveUrl) &&
                !isM3u8;
            if (!canFallbackToDownloaded) {
              rethrow;
            }

            debugPrint(
              "[VideoManager] Primary init failed, trying local fallback -> "
              "$effectiveUrl ($streamError)",
            );

            await safeDispose(player);

            final shouldForceFreshDownload =
                _shouldForceFreshDownloadAfterPrimaryInitFailure(
              usedStreaming: usedStreaming,
              isPreload: isPreload,
              isHls: isHls,
              url: effectiveUrl,
            );
            if (shouldForceFreshDownload) {
              if (file != null) {
                await _safeDeleteFile(file);
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
              final downloadResult = await _downloadVideo(
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

          if (autoPlay && !player.controller.value.isPlaying) {
            await player.controller.play().catchError((_) {});
          }

          stopwatch.stop();

          debugPrint(
            "[VideoManager] Init ${isPreload ? 'preload' : 'active'} "
            "${kIsWeb ? 'web' : _playbackBranch(
                isHls: isHls,
                usedCache: usedCache,
                usedStreaming: usedStreaming,
                usedStreamFallback: usedStreamFallback,
              )} "
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
              requestedHls: attemptHls,
              cacheBypassed: isHls ? true : null,
              playbackBranch: _playbackBranch(
                isHls: isHls,
                usedCache: usedCache,
                usedStreaming: usedStreaming,
                usedStreamFallback: usedStreamFallback,
              ),
              hlsSuppressedReason: hlsSuppressedReason,
              manifestHost: hlsDetails?.host,
              manifestPath: hlsDetails?.path,
              manifestHasToken: hlsDetails?.hasToken,
              usedStreaming: usedStreaming,
              usedStreamFallback: usedStreamFallback,
              fallbackFromSourceType: fallbackFromSourceType,
              recoveryReason: recoveryReason,
              primaryInitDuration: primaryInitDuration,
              fallbackDownloadDuration: fallbackDownloadDuration,
              fallbackInitDuration: fallbackInitDuration,
              fallbackCacheHit: usedStreamFallback ? fallbackCacheHit : null,
              reusedInFlightDownload:
                  usedStreamFallback ? reusedInFlightDownload : null,
            ),
          );

          if (_shouldWarmCacheAfterStreamInit(
            isHls: isHls,
            isPreload: isPreload,
            usedStreaming: usedStreaming,
            usedStreamFallback: usedStreamFallback,
          )) {
            unawaited(_warmCacheAfterPlaybackStabilizes(effectiveUrl));
          }

          unawaited(_checkCacheSizeThrottled());
          return player;
        } catch (e, st) {
          if (e is _VideoInitCancelled) {
            lru.remove(cacheKey);
            return Future.error(e);
          }
          debugPrint("❌ Video init error $effectiveUrl: $e\n$st");

          if (isHls) {
            debugPrint(
              '[VideoManager][HLS] init failed -> $effectiveUrl '
              '(cacheBypassed=true host=${hlsDetails?.host} '
              'path=${hlsDetails?.path} token=${hlsDetails?.hasToken} '
              'isPreload=$isPreload attemptedHls=$attemptHls '
              'fallbackFrom=$fallbackFromSourceType reason=$recoveryReason)',
            );
          }

          if (!kIsWeb && file != null) {
            unawaited(_safeDeleteFile(file));
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
              requestedHls: attemptHls,
              cacheBypassed: isHls ? true : null,
              playbackBranch: _playbackBranch(
                isHls: isHls,
                usedCache: usedCache,
                usedStreaming: usedStreaming,
                usedStreamFallback: usedStreamFallback,
              ),
              hlsSuppressedReason: hlsSuppressedReason,
              manifestHost: hlsDetails?.host,
              manifestPath: hlsDetails?.path,
              manifestHasToken: hlsDetails?.hasToken,
              recoveryReason: recoveryReason,
              primaryInitDuration: primaryInitDuration,
              fallbackDownloadDuration: fallbackDownloadDuration,
              fallbackInitDuration: fallbackInitDuration,
              fallbackCacheHit: usedStreamFallback ? fallbackCacheHit : null,
              reusedInFlightDownload:
                  usedStreamFallback ? reusedInFlightDownload : null,
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

  Future<_VideoDownloadResult> _downloadVideo(
    String url, {
    bool force = false,
  }) async {
    if (!force) {
      final inFlight = _downloadFuturesByUrl[url];
      if (inFlight != null) {
        final reuseStopwatch = Stopwatch()..start();
        final result = await inFlight;
        reuseStopwatch.stop();
        return _VideoDownloadResult(
          file: result.file,
          duration: reuseStopwatch.elapsed,
          reusedInFlight: true,
        );
      }
    }

    final future = _performDownloadVideo(url, force: force);
    _downloadFuturesByUrl[url] = future;

    try {
      return await future;
    } finally {
      if (identical(_downloadFuturesByUrl[url], future)) {
        _downloadFuturesByUrl.remove(url);
      }
    }
  }

  Future<_VideoDownloadResult> _performDownloadVideo(
    String url, {
    bool force = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final hasNet = await _hasConnectivity();
    if (!hasNet) throw Exception("No internet : $url");

    if (force) {
      final cached = await custom_cache.VideoCacheManager.getFileIfCached(url);
      if (cached != null && await cached.exists()) {
        await _safeDeleteFile(cached);
      }
    }

    final isFirebaseStorage = _isFirebaseStorageUrl(url);
    final maxAttempts = isFirebaseStorage ? _firebaseDownloadMaxAttempts : 1;

    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final info = await custom_cache.VideoCacheManager.getInstance().then(
          (m) => m.downloadFile(
            url,
            force: force || attempt > 1,
          ),
        );

        if (attempt > 1) {
          debugPrint(
            "[VideoManager] Firebase download recovered on attempt "
            "$attempt/$maxAttempts -> $url",
          );
        }
        stopwatch.stop();
        return _VideoDownloadResult(
          file: info.file,
          duration: stopwatch.elapsed,
          reusedInFlight: false,
        );
      } catch (e, st) {
        lastError = e;
        lastStackTrace = st;

        final shouldRetry = isFirebaseStorage &&
            attempt < maxAttempts &&
            _isRetryableFirebaseDownloadError(e);

        if (!shouldRetry) {
          rethrow;
        }

        final delay = _firebaseRetryDelay(attempt);
        debugPrint(
          "[VideoManager] Firebase download retry $attempt/$maxAttempts "
          "in ${delay.inMilliseconds}ms -> $url ($e)",
        );
        await Future.delayed(delay);
      }
    }

    if (lastError != null && lastStackTrace != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace);
    }
    throw Exception("Download failed without explicit error: $url");
  }

  Future<void> _warmCacheInBackground(String url) async {
    try {
      await _downloadVideo(url);
    } catch (e) {
      debugPrint(
        "[VideoManager] Background cache warmup failed for $url: $e",
      );
    }
  }

  Future<void> _warmCacheAfterPlaybackStabilizes(String url) async {
    await Future<void>.delayed(_postInitStreamCacheWarmupDelay);
    await _warmCacheInBackground(url);
  }

  Future<void> _safeDeleteFile(File file) async {
    try {
      await file.delete();
    } catch (_) {}
  }

  bool _isFirebaseStorageUrl(String url) {
    try {
      final host = Uri.parse(url).host.toLowerCase();
      return host == _firebaseStorageHost;
    } catch (_) {
      return false;
    }
  }

  bool _isRetryableFirebaseDownloadError(Object error) {
    if (error is TimeoutException) return true;
    if (error is SocketException) return true;
    if (error is HandshakeException) return true;
    if (error is http.ClientException) return true;
    if (error is HttpException) return true;
    if (error is HttpExceptionWithStatus) {
      final status = error.statusCode;
      return status == 408 || status == 429 || (status >= 500 && status < 600);
    }

    final message = error.toString().toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('connection timed out') ||
        message.contains('connection reset') ||
        message.contains('temporarily unavailable') ||
        message.contains('network is unreachable') ||
        message.contains('timed out');
  }

  Duration _firebaseRetryDelay(int attempt) {
    final exp = attempt - 1;
    final baseMs = _firebaseRetryBaseDelay.inMilliseconds * (1 << exp);
    final cappedMs = baseMs > _firebaseRetryMaxDelay.inMilliseconds
        ? _firebaseRetryMaxDelay.inMilliseconds
        : baseMs;
    final jitterMs = _retryRandom.nextInt(220);
    return Duration(milliseconds: cappedMs + jitterMs);
  }

  Future<void> _readAndReportCacheSize() async {
    if (!kIsWeb) {
      final size = await _cacheSizeProvider();
      if (size > custom_cache.VideoCacheManager.maxCacheSizeMB) {
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
    final lru = _lruByContext[contextKey];
    if (lru == null) return;
    final resolvedActive =
        activeUrl != null ? _resolveKey(contextKey, activeUrl) : null;

    while (lru.length > _maxActive) {
      final oldestKey =
          lru.keys.firstWhere((k) => k != resolvedActive, orElse: () => '');
      if (oldestKey.isEmpty) break;

      final player = lru.remove(oldestKey);
      if (player == null) continue;
      await safePause(player);
      await safeDispose(player);

      _initFuturesByContext[contextKey]?.remove(oldestKey);

      for (final original in _originalUrlsForResolved(contextKey, oldestKey)) {
        _removeUiTracking(contextKey, original);
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
    bool preferForward = true,
  }) async {
    _ensureNetworkProfileWarm();
    final radius = _preloadRadius;
    if (radius <= 0) return;

    for (final candidateIndex in preloadOrderForTests(
      totalVideos: videos.length,
      index: index,
      radius: radius,
      preferForward: preferForward,
    )) {
      final v = videos[candidateIndex];
      unawaited(
        initializeController(
          contextKey,
          v.videoUrl,
          sources: v.sources,
          useHls: useHls && v.hasAdaptiveHlsSource,
          isPreload: true,
          activeUrl: activeUrl,
        ),
      );
    }
  }

  @visibleForTesting
  List<int> preloadOrderForTests({
    required int totalVideos,
    required int index,
    required int radius,
    bool preferForward = true,
  }) {
    if (totalVideos <= 0 || radius <= 0) {
      return const [];
    }
    if (index < 0 || index >= totalVideos) {
      return const [];
    }

    final ordered = <int>[];
    for (int distance = 1; distance <= radius; distance++) {
      final previousIndex = index - distance;
      final nextIndex = index + distance;

      if (preferForward) {
        if (nextIndex < totalVideos) {
          ordered.add(nextIndex);
        }
        if (previousIndex >= 0) {
          ordered.add(previousIndex);
        }
      } else {
        if (previousIndex >= 0) {
          ordered.add(previousIndex);
        }
        if (nextIndex < totalVideos) {
          ordered.add(nextIndex);
        }
      }
    }

    return ordered;
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

  ValueListenable<int> watchVideoUi(String contextKey, String url) {
    final byUrl = _uiWatchersByContext.putIfAbsent(contextKey, () => {});
    final entry = byUrl.putIfAbsent(url, _VideoUiWatchEntry.new);
    entry.watcherCount++;
    return entry.notifier;
  }

  void unwatchVideoUi(String contextKey, String url) {
    final byUrl = _uiWatchersByContext[contextKey];
    final entry = byUrl?[url];
    if (entry == null) {
      return;
    }

    entry.watcherCount--;
    if (entry.watcherCount > 0) {
      return;
    }

    entry.notifier.dispose();
    byUrl?.remove(url);
    if (byUrl != null && byUrl.isEmpty) {
      _uiWatchersByContext.remove(contextKey);
    }
  }

  List<String> activeOriginalUrlsForContext(String contextKey) {
    final lru = _lruByContext[contextKey];
    final resolvedByOriginal = _resolvedUrlByContext[contextKey];
    if (lru == null || lru.isEmpty || resolvedByOriginal == null) {
      return const [];
    }

    final activeResolvedUrls = lru.keys.toSet();
    return resolvedByOriginal.entries
        .where((entry) => activeResolvedUrls.contains(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  Future<void> pauseAllExcept(String contextKey, String? keepUrl) async {
    final lru = _lruByContext[contextKey] ?? {};
    final resolvedKeep =
        keepUrl != null ? _resolveKey(contextKey, keepUrl) : null;

    for (final entry in lru.entries.toList()) {
      if (entry.key == resolvedKeep) continue;
      bool isInitialized = false;
      try {
        isInitialized = entry.value.controller.value.isInitialized;
      } catch (_) {
        isInitialized = false;
      }
      if (isInitialized) {
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
    _notifyUiStateChanged();
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
      _removeUiTracking(contextKey, url);
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
