// ignore_for_file: body_might_complete_normally_catch_error

import 'dart:async';
import 'dart:collection';
import 'dart:io' show File;
import 'package:flutter/foundation.dart'; // kIsWeb, debugPrint
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:adfoot/utils/video_cache_manager.dart';

enum VideoLoadState { loading, ready, errorTimeout, errorSource }

class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal();

  final Map<String, LinkedHashMap<String, CachedVideoPlayerPlus>> _lruByContext = {};
  final Map<String, Map<String, Future<CachedVideoPlayerPlus>>> _initFuturesByContext = {};
  final Map<String, Map<String, VideoLoadState>> _loadStatesByContext = {};

  /// 🔧 LRU stricte
  final int _maxActive = 8;

  /// 🔧 Limite du nombre d’inits simultanées
  int _activeInits = 0;
  final int _maxConcurrentInits = 3;

  Future<CachedVideoPlayerPlus> initializeController(
    String contextKey,
    String url, {
    bool isPreload = false,
    bool autoPlay = false,
    String? activeUrl,
  }) async {
    _loadStatesByContext.putIfAbsent(contextKey, () => {})[url] = VideoLoadState.loading;
    _lruByContext.putIfAbsent(contextKey, () => LinkedHashMap());
    _initFuturesByContext.putIfAbsent(contextKey, () => {});

    final futures = _initFuturesByContext[contextKey]!;
    final lru = _lruByContext[contextKey]!;

    // ✅ Déjà en cache et valide
    if (lru.containsKey(url)) {
      final existing = lru.remove(url)!;
      final cv = existing.controller.value;
      if (cv.isInitialized && !cv.hasError) {
        lru[url] = existing; // remet en fin de LRU
        await _enforceLimit(contextKey, activeUrl: activeUrl);
        _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
        if (autoPlay && !cv.isPlaying) await existing.controller.play().catchError((_) {});
        return existing;
      }
      await safeDispose(existing);
      lru.remove(url);
    }

    // ✅ Init déjà en cours
    if (futures.containsKey(url)) {
      try {
        final player = await futures[url]!;
        final cv = player.controller.value;
        if (cv.isInitialized && !cv.hasError) {
          lru[url] = player;
          await _enforceLimit(contextKey, activeUrl: activeUrl);
          _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
          if (autoPlay && !cv.isPlaying) await player.controller.play().catchError((_) {});
          return player;
        }
      } catch (_) {}
      futures.remove(url);
      lru.remove(url);
    }

    // ✅ Nouvelle init contrôlée par sémaphore
    Future<CachedVideoPlayerPlus> loadVideo() async {
      final stopwatch = Stopwatch()..start();
      File? file;
      try {
        final timeout = isPreload ? const Duration(seconds: 8) : const Duration(seconds: 12);
        CachedVideoPlayerPlus player;

        if (kIsWeb) {
          player = CachedVideoPlayerPlus.networkUrl(Uri.parse(url));
        } else {
          file = await VideoCacheManager.getFileIfCached(url);

          // retry si cache corrompu
          if (file == null || !(await file.exists())) {
            file = await _downloadVideo(url, force: true);
          }

          if (!await file.exists()) throw Exception("Fichier introuvable : $url");
          player = CachedVideoPlayerPlus.file(file);
        }

        await player.initialize().timeout(timeout, onTimeout: () {
          _loadStatesByContext[contextKey]![url] = VideoLoadState.errorTimeout;
          throw TimeoutException("Init timeout : $url");
        });

        final v = player.controller.value;
        if (!v.isInitialized || v.hasError) {
          if (!kIsWeb && file != null) unawaited(file.delete().catchError((_) {}));
          throw Exception("Init error : $url");
        }

        player.controller.setLooping(true);
        lru[url] = player;
        await _enforceLimit(contextKey, activeUrl: activeUrl);
        _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;

        if (autoPlay && !player.controller.value.isPlaying) {
          await player.controller.play().catchError((_) {});
        }

        stopwatch.stop();
        debugPrint("[VideoManager] Init $url in ${stopwatch.elapsedMilliseconds}ms");
        return player;
      } catch (e, st) {
        debugPrint("❌ Video init error $url: $e\n$st");
        _loadStatesByContext[contextKey]![url] = VideoLoadState.errorSource;
        lru.remove(url);
        return Future.error(e);
      }
    }

    // ✅ Gestion sémaphore
    while (_activeInits >= _maxConcurrentInits) {
      await Future.delayed(const Duration(milliseconds: 80));
    }

    _activeInits++;
    final future = loadVideo().whenComplete(() => _activeInits--);
    futures[url] = future;

    try {
      final result = await future;
      futures.remove(url);
      unawaited(_checkCacheSize());
      return result;
    } catch (e) {
      futures.remove(url);
      lru.remove(url);
      rethrow;
    }
  }

  Future<File> _downloadVideo(String url, {bool force = false}) async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) throw Exception("No internet : $url");

    if (force) {
      final cached = await VideoCacheManager.getFileIfCached(url);
      if (cached != null && await cached.exists()) {
        await cached.delete().catchError((_) {});
      }
    }

    final info = await VideoCacheManager.getInstance().then((m) => m.downloadFile(url));
    return info.file;
  }

  Future<void> _enforceLimit(String contextKey, {String? activeUrl}) async {
    final lru = _lruByContext[contextKey]!;
    while (lru.length > _maxActive) {
      final oldestKey = lru.keys.firstWhere((k) => k != activeUrl, orElse: () => '');
      if (oldestKey.isEmpty) break;
      final player = lru.remove(oldestKey)!;
      await safePause(player);
      await safeDispose(player);
      _initFuturesByContext[contextKey]?.remove(oldestKey);
      _loadStatesByContext[contextKey]?.remove(oldestKey);
      debugPrint("[VideoManager] Disposed LRU controller: $oldestKey");
    }
  }

  Future<void> _checkCacheSize() async {
    if (!kIsWeb) {
      final size = await VideoCacheManager.getCacheSizeInMB();
      if (size > 300) debugPrint("⚠️ Cache >300MB: ${size}MB");
    }
  }

  Future<void> pauseAllExcept(String contextKey, String? keepUrl) async {
    final lru = _lruByContext[contextKey] ?? {};
    for (final entry in lru.entries) {
      if (entry.key != keepUrl && entry.value.controller.value.isInitialized) {
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
  }

  Future<void> disposeUrls(String contextKey, List<String> urls) async {
    final lru = _lruByContext[contextKey];
    if (lru == null) return;
    for (var url in urls) {
      final player = lru.remove(url);
      if (player != null) {
        await safePause(player);
        await safeDispose(player);
        debugPrint("[VideoManager] Disposed URL: $url");
      }
      _initFuturesByContext[contextKey]?.remove(url);
      _loadStatesByContext[contextKey]?.remove(url);
    }
  }

  CachedVideoPlayerPlus? getController(String contextKey, String url) {
    final player = _lruByContext[contextKey]?[url];
    if (player == null) return null;
    final v = player.controller.value;
    if (!v.isInitialized || v.hasError) return null;
    return player;
  }

  VideoLoadState? getLoadState(String contextKey, String url) =>
      _loadStatesByContext[contextKey]?[url];

  Future<void> preloadSurrounding(
    String contextKey,
    List<String> urls,
    int index, {
    String? activeUrl,
  }) async {
    int radius = 1;
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.wifi || conn == ConnectivityResult.ethernet) radius = 2;

    for (int i = 1; i <= radius; i++) {
      if (index - i >= 0) {
        unawaited(initializeController(contextKey, urls[index - i], isPreload: true, activeUrl: activeUrl));
      }
      if (index + i < urls.length) {
        unawaited(initializeController(contextKey, urls[index + i], isPreload: true, activeUrl: activeUrl));
      }
    }
  }

  Future<void> safePause(CachedVideoPlayerPlus player) async {
    try {
      final c = player.controller;
      if (c.value.isInitialized && c.value.isPlaying) await c.pause();
    } catch (_) {}
  }

  Future<void> safeDispose(CachedVideoPlayerPlus player) async {
    try {
      await player.dispose();
    } catch (_) {}
  }

  Future<void> waitUntilInitialized(String contextKey, String url) async {
    final player = _lruByContext[contextKey]?[url];
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
      await completer.future.timeout(const Duration(seconds: 12));
    } catch (_) {
      c.removeListener(listener);
    }
  }
}
