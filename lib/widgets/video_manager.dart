import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';

class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal();

  final Map<String, CachedVideoPlayerPlusController> _controllers = {};
  final Map<String, Future<CachedVideoPlayerPlusController>> _initializationFutures = {};
  final Map<String, CancelToken> _downloadCancelTokens = {};
  final List<String> _recentUrls = [];

  final int _maxCacheVideos = 3;
  DateTime? _lastCleanup;

  Future<CachedVideoPlayerPlusController> initializeController(String url) async {
    if (_controllers.containsKey(url)) {
      final controller = _controllers[url]!;
      if (controller.value.isInitialized && !controller.value.hasError) {
        _markAsRecentlyUsed(url);
        return controller;
      } else {
        await controller.dispose();
        _controllers.remove(url);
      }
    }

    if (_initializationFutures.containsKey(url)) {
      return await _initializationFutures[url]!;
    }

    final initialization = _createCachedController(url);
    _initializationFutures[url] = initialization;

    final controller = await initialization;
    _controllers[url] = controller;
    _initializationFutures.remove(url);
    _markAsRecentlyUsed(url);
    _enforceMemoryLimit();

    return controller;
  }

  Future<CachedVideoPlayerPlusController> _createCachedController(String url) async {
    final file = await _getOrDownloadVideo(url);
    final controller = CachedVideoPlayerPlusController.file(file);
    await controller.initialize();
    controller.setLooping(true);
    return controller;
  }

  Future<File> _getOrDownloadVideo(String url) async {
    await _cleanOldCachedVideos();

    final cacheDir = await getTemporaryDirectory();
    final fileName = Uri.parse(url).pathSegments.last;
    final filePath = '${cacheDir.path}/$fileName';
    final file = File(filePath);

    if (await file.exists()) {
      return file;
    }

    final cancelToken = CancelToken();
    _downloadCancelTokens[url] = cancelToken;

    try {
      final response = await Dio().download(url, file.path, cancelToken: cancelToken);
      _downloadCancelTokens.remove(url);

      if (response.statusCode == 200) {
        return file;
      } else {
        throw Exception('Échec téléchargement : ${response.statusCode}');
      }
    } catch (e) {
      if (await file.exists()) return file;
      throw Exception('Téléchargement échoué : $e');
    }
  }

  Future<void> _cleanOldCachedVideos() async {
    final now = DateTime.now();
    if (_lastCleanup != null && now.difference(_lastCleanup!) < const Duration(hours: 2)) {
      return;
    }

    _lastCleanup = now;
    try {
      final cacheDir = await getTemporaryDirectory();
      final files = cacheDir.listSync();

      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          final modified = stat.modified;
          if (now.difference(modified) > const Duration(hours: 2)) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> preload(String url) async {
    if (_controllers.length >= _maxCacheVideos || _controllers.containsKey(url)) return;
    try {
      await initializeController(url);
    } catch (_) {}
  }

  void pause(String url) {
    final controller = _controllers[url];
    if (controller != null && controller.value.isInitialized && controller.value.isPlaying) {
      controller.pause();
    }
  }

  void _markAsRecentlyUsed(String url) {
    _recentUrls.remove(url);
    _recentUrls.add(url);
  }

  void _enforceMemoryLimit() {
    while (_recentUrls.length > _maxCacheVideos) {
      final oldestUrl = _recentUrls.removeAt(0);
      dispose(oldestUrl);
    }
  }

  void cancelDownload(String url) {
    if (_downloadCancelTokens.containsKey(url)) {
      _downloadCancelTokens[url]?.cancel("Téléchargement annulé.");
      _downloadCancelTokens.remove(url);
    }
  }

  void dispose(String url) {
    cancelDownload(url);
    final controller = _controllers.remove(url);
    if (controller != null && controller.value.isInitialized) {
      controller.dispose();
    }
    _initializationFutures.remove(url);
    _recentUrls.remove(url);
  }

  void disposeAllExcept(String urlToKeep) {
    final urlsToDispose = _controllers.keys.where((url) => url != urlToKeep).toList();
    for (final url in urlsToDispose) {
      dispose(url);
    }
  }

  void disposeAll() {
    for (final url in _controllers.keys.toList()) {
      dispose(url);
    }
  }

  bool hasController(String url) => _controllers.containsKey(url);

  CachedVideoPlayerPlusController? getController(String url) {
    final controller = _controllers[url];
    if (controller != null && controller.value.isInitialized && !controller.value.hasError) {
      return controller;
    }
    return null;
  }
}
