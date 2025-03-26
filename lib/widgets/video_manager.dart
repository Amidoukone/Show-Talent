import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  final Map<String, VideoPlayerController> _controllers = {};
  static const int _maxCacheCount = 5;

  factory VideoManager() => _instance;

  VideoManager._internal();

  Future<VideoPlayerController> getController(String url) async {
    if (_controllers.containsKey(url)) return _controllers[url]!;

    final controller = await _initController(url);
    _controllers[url] = controller;
    _cleanupOldControllers();
    return controller;
  }

  Future<VideoPlayerController> _initController(String url) async {
    final cache = DefaultCacheManager();
    File file;
    final cachedFile = await cache.getFileFromCache(url);

    if (cachedFile != null && await cachedFile.file.exists()) {
      file = cachedFile.file;
    } else {
      file = await cache.getSingleFile(url);
    }

    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    controller.setLooping(true);
    return controller;
  }

  void play(String url) {
    _controllers.forEach((key, controller) {
      if (key == url) {
        if (!controller.value.isPlaying) controller.play();
      } else {
        if (controller.value.isPlaying) controller.pause();
      }
    });
  }

  void pause(String url) {
    _controllers[url]?.pause();
  }

  void preload(String url) {
    if (!_controllers.containsKey(url)) {
      _initController(url).then((controller) {
        _controllers[url] = controller;
        _cleanupOldControllers();
      }).catchError((_) {});
    }
  }

  void releaseController(String url) {
    _controllers[url]?.dispose();
    _controllers.remove(url);
  }

  void _cleanupOldControllers() {
    if (_controllers.length <= _maxCacheCount) return;
    final keys = _controllers.keys.take(_controllers.length - _maxCacheCount);
    for (final key in keys) {
      _controllers[key]?.dispose();
      _controllers.remove(key);
    }
  }
}
