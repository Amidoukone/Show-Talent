import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:adfoot/utils/video_cache_manager.dart';

enum VideoLoadState { loading, ready, errorTimeout, errorSource }

class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal();

  final Map<String, Map<String, CachedVideoPlayerPlus>> _playersByContext = {};
  final Map<String, Map<String, Future<CachedVideoPlayerPlus>>> _initFuturesByContext = {};
  final Map<String, List<String>> _recentByContext = {};
  final Map<String, Map<String, VideoLoadState>> _loadStatesByContext = {};
  final int _maxActive = 10;

  Future<CachedVideoPlayerPlus> initializeController(
    String contextKey,
    String url, {
    bool isPreload = false,
    bool autoPlay = false,
    String? activeUrl,
  }) async {
    _loadStatesByContext.putIfAbsent(contextKey, () => {})[url] = VideoLoadState.loading;
    _playersByContext.putIfAbsent(contextKey, () => {});
    _initFuturesByContext.putIfAbsent(contextKey, () => {});
    _recentByContext.putIfAbsent(contextKey, () => <String>[]);

    final futures = _initFuturesByContext[contextKey]!;

    // Déjà prêt ?
    final existing = _playersByContext[contextKey]![url];
    if (existing != null) {
      final cv = existing.controller.value;
      if (cv.isInitialized && !cv.hasError) {
        _markRecent(contextKey, url);
        await _enforceLimit(contextKey, activeUrl: activeUrl);
        _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
        if (autoPlay && !cv.isPlaying) await existing.controller.play();
        return existing;
      } else {
        await safeDispose(existing);
        _playersByContext[contextKey]!.remove(url);
      }
    }

    // Init en cours ?
    if (futures.containsKey(url)) {
      final player = await futures[url]!;
      final cv = player.controller.value;
      if (cv.isInitialized && !cv.hasError) {
        _markRecent(contextKey, url);
        await _enforceLimit(contextKey, activeUrl: activeUrl);
        _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
        if (autoPlay && !cv.isPlaying) await player.controller.play();
        return player;
      } else {
        futures.remove(url);
        _playersByContext[contextKey]?.remove(url);
      }
    }

    Future<CachedVideoPlayerPlus> loadVideo() async {
      File? file;
      try {
        file = await VideoCacheManager.getFileIfCached(url);
        if (file == null || !await file.exists()) {
          file = await _downloadVideo(url);
        }
        if (!await file.exists()) throw Exception("Fichier introuvable : $url");

        final player = CachedVideoPlayerPlus.file(file);

        // Timeout un peu plus large
        await player.initialize().timeout(
          const Duration(seconds: 12),
          onTimeout: () {
            _loadStatesByContext[contextKey]![url] = VideoLoadState.errorTimeout;
            throw TimeoutException("Timeout init : $url");
          },
        );

        if (!player.controller.value.isInitialized || player.controller.value.hasError) {
          try { await file.delete(); } catch (_) {}
          throw Exception("Erreur initialisation player : $url");
        }

        player.controller.setLooping(true);
        _playersByContext[contextKey]![url] = player;
        _markRecent(contextKey, url);
        await _enforceLimit(contextKey, activeUrl: activeUrl);
        _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
        if (autoPlay && !player.controller.value.isPlaying) {
          await player.controller.play();
        }
        return player;
      } catch (e, st) {
        debugPrint("❌ Video init error: $e\n$st");
        _loadStatesByContext[contextKey]![url] = VideoLoadState.errorSource;
        _playersByContext[contextKey]?.remove(url);
        return Future.error(Exception("Erreur vidéo : $url\n$e"));
      }
    }

    final future = loadVideo();
    futures[url] = future;

    try {
      final result = await future;
      futures.remove(url);
      unawaited(_checkCacheSize());
      return result;
    } catch (e) {
      futures.remove(url);
      _playersByContext[contextKey]?.remove(url);
      rethrow;
    }
  }

  Future<File> _downloadVideo(String url) async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) {
      throw Exception("Pas de connexion Internet pour télécharger : $url");
    }
    final info = await VideoCacheManager.getInstance().then((m) => m.downloadFile(url));
    if (await info.file.exists()) return info.file;
    throw Exception("Téléchargement échoué : $url");
  }

  void _markRecent(String contextKey, String url) {
    final recent = _recentByContext[contextKey]!;
    recent.remove(url);
    recent.add(url);
  }

  Future<void> _enforceLimit(String contextKey, {String? activeUrl}) async {
    final recent = _recentByContext[contextKey]!;
    // Purge tant qu'on dépasse, en évitant activeUrl
    while (recent.length > _maxActive) {
      final oldest = recent.firstWhere((u) => u != activeUrl, orElse: () => '');
      if (oldest.isEmpty) break;
      recent.remove(oldest);
      final player = _playersByContext[contextKey]?.remove(oldest);
      if (player != null) {
        await safePause(player);
        await Future.delayed(const Duration(milliseconds: 50));
        await safeDispose(player);
        debugPrint("Disposed controller for: $oldest");
      }
      _initFuturesByContext[contextKey]?.remove(oldest);
      _loadStatesByContext[contextKey]?.remove(oldest);
    }
  }

  Future<void> _checkCacheSize() async {
    final size = await VideoCacheManager.getCacheSizeInMB();
    if (size > 300) debugPrint("⚠️ Cache >300MB (${size}MB)");
  }

  Future<void> pauseAllExcept(String contextKey, String? keepUrl) async {
    final map = _playersByContext[contextKey] ?? {};
    for (final entry in map.entries) {
      if (entry.key != keepUrl && entry.value.controller.value.isInitialized) {
        await safePause(entry.value);
      }
    }
  }

  Future<void> pauseAll(String contextKey) async {
    final map = _playersByContext[contextKey] ?? {};
    for (final player in map.values) {
      await safePause(player);
    }
  }

  Future<void> disposeAllForContext(String contextKey) async {
    final map = _playersByContext.remove(contextKey);
    if (map != null) {
      for (final player in map.values) {
        await safePause(player);
        await Future.delayed(const Duration(milliseconds: 50));
        await safeDispose(player);
      }
    }
    _recentByContext.remove(contextKey);
    _loadStatesByContext.remove(contextKey);
    _initFuturesByContext.remove(contextKey);
  }

  Future<void> disposeUrls(String contextKey, List<String> urls) async {
    final map = _playersByContext[contextKey];
    if (map == null) return;

    for (final url in urls) {
      final player = map.remove(url);
      if (player != null) {
        await safePause(player);
        await Future.delayed(const Duration(milliseconds: 50));
        await safeDispose(player);
        debugPrint("Disposed URL: $url");
      }
      _initFuturesByContext[contextKey]?.remove(url);
      _loadStatesByContext[contextKey]?.remove(url);
      _recentByContext[contextKey]?.remove(url);
    }
  }

  bool hasController(String contextKey, String url) =>
      _playersByContext[contextKey]?.containsKey(url) ?? false;

  CachedVideoPlayerPlus? getController(String contextKey, String url) {
    final player = _playersByContext[contextKey]?[url];
    if (player == null || !player.controller.value.isInitialized || player.controller.value.hasError) {
      return null;
    }
    return player;
  }

  VideoLoadState? getLoadState(String contextKey, String url) =>
      _loadStatesByContext[contextKey]?[url];

  Future<void> preloadSurrounding(String contextKey, List<String> urls, int index,
      {String? activeUrl}) async {
    for (int i = 1; i <= 2; i++) {
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
      if (player.controller.value.isInitialized && player.controller.value.isPlaying) {
        await player.controller.pause();
      }
    } catch (_) {}
  }

  Future<void> safeDispose(CachedVideoPlayerPlus player) async {
    try {
      if (player.controller.value.isInitialized || player.controller.value.hasError) {
        await player.dispose();
      }
    } catch (_) {}
  }

  // === Ajout : attente d'initialisation ===
  Future<void> waitUntilInitialized(String contextKey, String url) async {
    final p = _playersByContext[contextKey]?[url];
    if (p == null) return;
    final c = p.controller;
    if (c.value.isInitialized) return;

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
