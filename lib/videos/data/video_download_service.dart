import 'dart:async';
import 'dart:io' show File, HandshakeException, HttpException, SocketException;
import 'dart:math' show Random;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show HttpExceptionWithStatus;
import 'package:http/http.dart' as http;

import 'package:adfoot/services/app_logger.dart';
import 'package:adfoot/utils/video_cache_manager.dart' as custom_cache;

/// One completed download, and what it cost.
class VideoDownloadResult {
  const VideoDownloadResult({
    required this.file,
    required this.duration,
    required this.reusedInFlight,
  });

  final File file;
  final Duration duration;

  /// True when this call joined a transfer that was already running rather
  /// than starting a second one for the same bytes.
  final bool reusedInFlight;
}

/// Gets a video file onto disk, and keeps the disk cache within its budget.
///
/// Split out of `VideoManager`, which held this alongside the controller LRU,
/// the initialisation pipeline, the preload scheduler, the bandwidth
/// arbitration, the network profile, the UI notifications and the metrics.
/// This part has a boundary the others do not: a URL goes in, a file comes
/// out, and nothing about players or contexts is involved.
class VideoDownloadService {
  VideoDownloadService();

  static const String _firebaseStorageHost = 'firebasestorage.googleapis.com';
  static const int _firebaseDownloadMaxAttempts = 4;
  static const Duration _firebaseRetryBaseDelay = Duration(milliseconds: 350);
  static const Duration _firebaseRetryMaxDelay = Duration(seconds: 3);
  static const Duration _cacheSizeCheckThrottle = Duration(minutes: 5);
  static const Duration _postInitStreamCacheWarmupDelay = Duration(seconds: 2);

  final Random _retryRandom = Random();

  /// In-flight transfers, keyed by URL.
  ///
  /// Two neighbours preloading the same video, or a fallback racing a
  /// preload, must not open two connections for identical bytes.
  final Map<String, Future<VideoDownloadResult>> _inFlightByUrl = {};

  Future<int> Function() _cacheSizeProvider =
      custom_cache.VideoCacheManager.getCacheSizeInMB;
  DateTime Function() _nowProvider = DateTime.now;
  DateTime? _lastCacheSizeCheckAt;
  Future<void>? _cacheSizeCheckFuture;

  /// True when [url] is served by Firebase Storage, which is the only host
  /// whose transient failures this service retries.
  static bool isFirebaseStorageUrl(String url) {
    try {
      return Uri.parse(url).host.toLowerCase() == _firebaseStorageHost;
    } catch (_) {
      return false;
    }
  }

  static Future<void> safeDeleteFile(File file) async {
    try {
      await file.delete();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------------

  Future<VideoDownloadResult> download(String url, {bool force = false}) async {
    if (!force) {
      final inFlight = _inFlightByUrl[url];
      if (inFlight != null) {
        final reuseStopwatch = Stopwatch()..start();
        final result = await inFlight;
        reuseStopwatch.stop();
        return VideoDownloadResult(
          file: result.file,
          duration: reuseStopwatch.elapsed,
          reusedInFlight: true,
        );
      }
    }

    final future = _performDownload(url, force: force);
    _inFlightByUrl[url] = future;

    try {
      return await future;
    } finally {
      if (identical(_inFlightByUrl[url], future)) {
        _inFlightByUrl.remove(url);
      }
    }
  }

  Future<VideoDownloadResult> _performDownload(
    String url, {
    bool force = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final hasNet = await _hasConnectivity();
    if (!hasNet) throw Exception("No internet : $url");

    if (force) {
      final cached = await custom_cache.VideoCacheManager.getFileIfCached(url);
      if (cached != null && await cached.exists()) {
        await safeDeleteFile(cached);
      }
    }

    final isFirebaseStorage = isFirebaseStorageUrl(url);
    final maxAttempts = isFirebaseStorage ? _firebaseDownloadMaxAttempts : 1;

    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final info = await custom_cache.VideoCacheManager.getInstance().then(
          (m) => m.downloadFile(url, force: force || attempt > 1),
        );

        if (attempt > 1) {
          AppLogger.debug(
            "[VideoDownloadService] Firebase download recovered on attempt "
            "$attempt/$maxAttempts -> $url",
          );
        }
        stopwatch.stop();
        return VideoDownloadResult(
          file: info.file,
          duration: stopwatch.elapsed,
          reusedInFlight: false,
        );
      } catch (e, st) {
        lastError = e;
        lastStackTrace = st;

        final shouldRetry =
            isFirebaseStorage &&
            attempt < maxAttempts &&
            _isRetryableFirebaseDownloadError(e);

        if (!shouldRetry) {
          rethrow;
        }

        final delay = _firebaseRetryDelay(attempt);
        AppLogger.debug(
          "[VideoDownloadService] Firebase download retry $attempt/$maxAttempts "
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

  /// How many neighbour files may be pulled off the network at once.
  ///
  /// A warm is a whole-file download, and it was the one path that took the
  /// connection without asking. Preloads used to run through
  /// `VideoManager.initializeController`, which queues on the tier's
  /// `maxConcurrentInits` — 3 on a high-tier network, 1 on a low one. Moving
  /// the far neighbours onto [warmFile], so they stop opening hardware
  /// decoders, took them out from under that gate at the same time: a radius
  /// of 3 starts five of them inside 700 ms, unthrottled, against the video
  /// the user is watching. That is the pause/resume loop this pipeline has
  /// already been fixed for twice, arriving by a third route.
  ///
  /// Over the limit a warm is dropped rather than queued. The scheduler runs
  /// again on every index change, and the neighbour that was dropped is
  /// nearer by then — so the cache still fills in the direction of travel,
  /// while a queue would hold the connection for pages the user has left.
  static const int maxConcurrentWarms = 2;

  int _activeWarms = 0;

  /// Puts [url]'s bytes on disk, if the connection has room for it.
  ///
  /// A cached file makes the next swipe fast — the controller opens from
  /// local storage instead of the network — and it costs no decoder, which is
  /// the resource the device actually runs out of.
  Future<void> warmFile(String url) async {
    if (kIsWeb || url.isEmpty) return;
    // Checked and claimed with no `await` in between, which is what makes the
    // counter a limit rather than a suggestion.
    if (_activeWarms >= maxConcurrentWarms) return;
    _activeWarms++;

    try {
      final cached = await custom_cache.VideoCacheManager.getFileIfCached(url);
      if (cached != null && await cached.exists()) return;

      await download(url);
    } finally {
      _activeWarms--;
    }
  }

  Future<void> warmCacheInBackground(String url) async {
    try {
      await download(url);
    } catch (e) {
      AppLogger.debug(
        "[VideoDownloadService] Background cache warmup failed for $url: $e",
      );
    }
  }

  Future<void> warmCacheAfterPlaybackStabilizes(String url) async {
    await Future<void>.delayed(_postInitStreamCacheWarmupDelay);
    await warmCacheInBackground(url);
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

  // ---------------------------------------------------------------------------
  // Cache size policing
  // ---------------------------------------------------------------------------

  /// Scans the cache at most once per [_cacheSizeCheckThrottle].
  ///
  /// The scan walks every blob on disk, and it used to run after every single
  /// download.
  Future<void> checkCacheSizeThrottled({bool force = false}) async {
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

  Future<void> _readAndReportCacheSize() async {
    if (!kIsWeb) {
      final size = await _cacheSizeProvider();
      final limit = custom_cache.VideoCacheManager.maxCacheSizeMB;
      if (size > limit) {
        AppLogger.debug("⚠️ Cache >${limit}MB: ${size}MB");
        unawaited(custom_cache.VideoCacheManager.purgeIfNeeded());
      }
    }
  }

  /// Replaces the size probe and the clock the throttle reads.
  ///
  /// Not `@visibleForTesting`: `VideoManager` exposes the actual test seam
  /// and forwards to this, so marking it as such would only make production
  /// code that exists *for* the test look like a violation.
  void configureCacheSizeProbe({
    Future<int> Function()? cacheSizeProvider,
    DateTime Function()? nowProvider,
  }) {
    _cacheSizeProvider =
        cacheSizeProvider ?? custom_cache.VideoCacheManager.getCacheSizeInMB;
    _nowProvider = nowProvider ?? DateTime.now;
    _lastCacheSizeCheckAt = null;
    _cacheSizeCheckFuture = null;
  }
}
