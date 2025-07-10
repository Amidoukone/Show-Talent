import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:adfoot/utils/video_cache_manager.dart';

enum VideoLoadState {
  loading,
  ready,
  errorTimeout,
  errorSource,
}

class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal();

  final Map<String, Map<String, CachedVideoPlayerPlusController>> _controllersByContext = {};
  final Map<String, Map<String, Future<CachedVideoPlayerPlusController>>> _initFuturesByContext = {};
  final Map<String, List<String>> _recentByContext = {};
  final Map<String, Map<String, VideoLoadState>> _loadStatesByContext = {};

  final int _maxActive = 5;

  Future<CachedVideoPlayerPlusController> initializeController(
    String contextKey,
    String url, {
    bool isPreload = false,
  }) async {
    _loadStatesByContext.putIfAbsent(contextKey, () => {})[url] = VideoLoadState.loading;
    _controllersByContext.putIfAbsent(contextKey, () => {});
    _initFuturesByContext.putIfAbsent(contextKey, () => {});
    _recentByContext.putIfAbsent(contextKey, () => <String>[]);

    final futures = _initFuturesByContext[contextKey]!;

    if (_controllersByContext[contextKey]!.containsKey(url)) {
      final ctrl = _controllersByContext[contextKey]![url]!;
      if (ctrl.value.isInitialized && !ctrl.value.hasError) {
        _markRecent(contextKey, url);
        await _enforceLimit(contextKey);
        _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
        return ctrl;
      } else {
        await safeDispose(ctrl);
        _controllersByContext[contextKey]!.remove(url);
      }
    }

    if (futures.containsKey(url)) {
      return await futures[url]!;
    }

    Future<CachedVideoPlayerPlusController> loadVideo() async {
      try {
        final file = await _getCachedVideo(url);
        final controller = CachedVideoPlayerPlusController.file(file);
        await controller.initialize();
        controller.setLooping(true);

        _controllersByContext[contextKey]![url] = controller;
        _markRecent(contextKey, url);
        await _enforceLimit(contextKey);
        _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
        return controller;
      } catch (e, st) {
        debugPrint("Video init error for $url: $e\n$st");
        _loadStatesByContext[contextKey]![url] = VideoLoadState.errorSource;
        return Future.error(e);
      }
    }

    final futureCtrl = loadVideo();
    futures[url] = futureCtrl;

    try {
      final result = await futureCtrl;
      futures.remove(url);
      return result;
    } catch (e) {
      futures.remove(url);
      rethrow;
    }
  }

  Future<File> _getCachedVideo(String url) async {
    final cacheManager = VideoCacheManager();
    final cached = await cacheManager.getFileFromCache(url);
    if (cached != null && await cached.file.exists()) {
      return cached.file;
    }

    final file = await cacheManager.downloadAndCacheFile(url);
    if (file != null && await file.exists()) {
      return file;
    }

    throw Exception("Failed to download video: $url");
  }

  void _markRecent(String contextKey, String url) {
    final recentList = _recentByContext[contextKey]!;
    recentList.remove(url);
    recentList.add(url);
  }

  Future<void> _enforceLimit(String contextKey) async {
    final recent = _recentByContext[contextKey]!;
    while (recent.length > _maxActive) {
      final oldest = recent.removeAt(0);
      final ctrl = _controllersByContext[contextKey]?.remove(oldest);
      if (ctrl != null) {
        await safePause(ctrl);
        await safeDispose(ctrl);
      }
      _loadStatesByContext[contextKey]?.remove(oldest);
      _initFuturesByContext[contextKey]?.remove(oldest);
    }
  }

  Future<void> pauseAllExcept(String contextKey, String? urlToKeep) async {
    final ctx = _controllersByContext[contextKey];
    if (ctx == null) return;
    for (final entry in ctx.entries) {
      final ctrl = entry.value;
      if (entry.key != urlToKeep) {
        await safePause(ctrl);
      }
    }
  }

  Future<void> pauseAll(String contextKey) async {
    final ctx = _controllersByContext[contextKey];
    if (ctx == null) return;
    for (final ctrl in ctx.values) {
      await safePause(ctrl);
    }
  }

  Future<void> disposeAllForContext(String contextKey) async {
    final ctrls = _controllersByContext.remove(contextKey);
    if (ctrls != null) {
      for (final ctrl in ctrls.values) {
        await safePause(ctrl);
        await safeDispose(ctrl);
      }
    }
    _recentByContext.remove(contextKey);
    _loadStatesByContext.remove(contextKey);
    _initFuturesByContext.remove(contextKey);
  }

  bool hasController(String contextKey, String url) =>
      _controllersByContext[contextKey]?.containsKey(url) ?? false;

  CachedVideoPlayerPlusController? getController(String contextKey, String url) {
    final ctrl = _controllersByContext[contextKey]?[url];
    if (ctrl == null || ctrl.value.hasError || !ctrl.value.isInitialized) return null;
    return ctrl;
  }

  VideoLoadState? getLoadState(String contextKey, String url) =>
      _loadStatesByContext[contextKey]?[url];

  Future<void> preloadSurrounding(String contextKey, List<String> urls, int index) async {
    for (int i = 1; i <= 2; i++) {
      if (index - i >= 0) {
        unawaited(initializeController(contextKey, urls[index - i], isPreload: true));
      }
      if (index + i < urls.length) {
        unawaited(initializeController(contextKey, urls[index + i], isPreload: true));
      }
    }
  }

  Future<void> safePause(CachedVideoPlayerPlusController ctrl) async {
    try {
      if (ctrl.value.isInitialized && ctrl.value.isPlaying) {
        await ctrl.pause();
      }
    } catch (_) {}
  }

  Future<void> safeDispose(CachedVideoPlayerPlusController ctrl) async {
    try {
      if (ctrl.value.isInitialized) {
        await ctrl.dispose();
      }
    } catch (_) {}
  }
}
