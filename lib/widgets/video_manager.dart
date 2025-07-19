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

  final Map<String, Map<String, CachedVideoPlayerPlusController>> _controllersByContext = {};
  final Map<String, Map<String, Future<CachedVideoPlayerPlusController>>> _initFuturesByContext = {};
  final Map<String, List<String>> _recentByContext = {};
  final Map<String, Map<String, VideoLoadState>> _loadStatesByContext = {};
  final int _maxActive = 10;

  Future<CachedVideoPlayerPlusController> initializeController(
    String contextKey,
    String url, {
    bool isPreload = false,
    bool autoPlay = false,
    String? activeUrl,
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
        await _enforceLimit(contextKey, activeUrl: activeUrl);
        _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
        debugPrint("[VideoManager] Reuse existing controller for $url");
        if (autoPlay && !ctrl.value.isPlaying) await ctrl.play();
        return ctrl;
      } else {
        await safeDispose(ctrl);
        _controllersByContext[contextKey]!.remove(url);
      }
    }

    if (futures.containsKey(url)) {
      final existingCtrl = await futures[url]!;
      if (autoPlay && !existingCtrl.value.isPlaying) await existingCtrl.play();
      return existingCtrl;
    }

    Future<CachedVideoPlayerPlusController> loadVideo() async {
      try {
        final file = await VideoCacheManager.getFileIfCached(url) ?? await _downloadVideo(url);
        final controller = CachedVideoPlayerPlusController.file(file);

        await controller.initialize().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _loadStatesByContext[contextKey]![url] = VideoLoadState.errorTimeout;
            throw TimeoutException("Video initialize timeout for $url");
          },
        );

        controller.setLooping(true);
        _controllersByContext[contextKey]![url] = controller;
        _markRecent(contextKey, url);
        await _enforceLimit(contextKey, activeUrl: activeUrl);
        _loadStatesByContext[contextKey]![url] = VideoLoadState.ready;
        if (autoPlay) await controller.play();
        return controller;
      } catch (e, st) {
        debugPrint("[VideoManager] Video init error for $url: $e\n$st");
        _loadStatesByContext[contextKey]![url] = VideoLoadState.errorSource;
        return Future.error(e);
      }
    }

    final futureCtrl = loadVideo();
    futures[url] = futureCtrl;

    try {
      final result = await futureCtrl;
      futures.remove(url);
      await _checkCacheSize();
      return result;
    } catch (e) {
      futures.remove(url);
      rethrow;
    }
  }

  Future<File> _downloadVideo(String url) async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) throw Exception("No internet to download video");
    final downloadedInfo = await VideoCacheManager.getInstance().then((m) => m.downloadFile(url));
    if (await downloadedInfo.file.exists()) return downloadedInfo.file;
    throw Exception("Failed to download video: $url");
  }

  void _markRecent(String contextKey, String url) {
    final recentList = _recentByContext[contextKey]!;
    recentList.remove(url);
    recentList.add(url);
  }

  Future<void> _enforceLimit(String contextKey, {String? activeUrl}) async {
    final recent = _recentByContext[contextKey]!;
    while (recent.length > _maxActive) {
      final oldest = recent.first;
      if (oldest == activeUrl) break;
      recent.removeAt(0);
      final ctrl = _controllersByContext[contextKey]?.remove(oldest);
      if (ctrl != null) {
        await safePause(ctrl);
        await Future.delayed(const Duration(milliseconds: 50));
        await safeDispose(ctrl);
      }
      _loadStatesByContext[contextKey]?.remove(oldest);
      _initFuturesByContext[contextKey]?.remove(oldest);
      debugPrint("[VideoManager] Disposed old controller for $oldest");
    }
  }

  Future<void> _checkCacheSize() async {
    final size = await VideoCacheManager.getCacheSizeInMB();
    if (size > 300) {
      debugPrint("[VideoManager] Cache size $size MB > 300 MB — consider clearing or pruning");
    }
  }

  Future<void> pauseAllExcept(String contextKey, String? urlToKeep) async {
    final ctx = _controllersByContext[contextKey];
    if (ctx != null) {
      for (final entry in ctx.entries) {
        final ctrl = entry.value;
        if (entry.key != urlToKeep && ctrl.value.isInitialized) await safePause(ctrl);
      }
    }
  }

  Future<void> pauseAll(String contextKey) async {
    final ctx = _controllersByContext[contextKey];
    if (ctx != null) {
      for (final ctrl in ctx.values) {
        await safePause(ctrl);
      }
    }
  }

  Future<void> disposeAllForContext(String contextKey) async {
    final ctrls = _controllersByContext.remove(contextKey);
    if (ctrls != null) {
      for (final ctrl in ctrls.values) {
        await safePause(ctrl);
        await Future.delayed(const Duration(milliseconds: 50));
        await safeDispose(ctrl);
      }
    }
    _recentByContext.remove(contextKey);
    _loadStatesByContext.remove(contextKey);
    _initFuturesByContext.remove(contextKey);
  }

  /// ✅ AJOUTÉ : libère des vidéos précises dans un contexte
  Future<void> disposeUrls(String contextKey, List<String> urls) async {
    final ctrls = _controllersByContext[contextKey];
    if (ctrls == null) return;

    for (final url in urls) {
      final ctrl = ctrls.remove(url);
      if (ctrl != null) {
        await safePause(ctrl);
        await Future.delayed(const Duration(milliseconds: 50));
        await safeDispose(ctrl);
        debugPrint("[VideoManager] Disposed specific URL in context $contextKey => $url");
      }
      _initFuturesByContext[contextKey]?.remove(url);
      _loadStatesByContext[contextKey]?.remove(url);
      _recentByContext[contextKey]?.remove(url);
    }
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

  Future<void> safePause(CachedVideoPlayerPlusController ctrl) async {
    try {
      if (ctrl.value.isInitialized && ctrl.value.isPlaying) await ctrl.pause();
    } catch (_) {}
  }

  Future<void> safeDispose(CachedVideoPlayerPlusController ctrl) async {
    try {
      if (ctrl.value.isInitialized || ctrl.value.hasError) await ctrl.dispose();
    } catch (_) {}
  }
}
