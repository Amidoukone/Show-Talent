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
    if (_controllers.containsKey(url)) {
      final controller = _controllers[url]!;
      if (controller.value.isInitialized) {
        return controller;
      } else {
        await controller.initialize();
        return controller;
      }
    }

    final controller = await _initController(url);
    _controllers[url] = controller;
    _cleanupOldControllers();
    return controller;
  }

  Future<VideoPlayerController> _initController(String url) async {
    late VideoPlayerController controller;

    try {
      if (url.endsWith('.m3u8')) {
        // ✅ Correction ici
        controller = VideoPlayerController.networkUrl(Uri.parse(url));
      } else {
        final cache = DefaultCacheManager();
        File file;
        final cachedFile = await cache.getFileFromCache(url);

        if (cachedFile != null && await cachedFile.file.exists()) {
          file = cachedFile.file;
        } else {
          file = await cache.getSingleFile(url);
        }
        controller = VideoPlayerController.file(file);
      }

      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(1.0);
      return controller;
    } catch (e) {
      throw Exception('Erreur initialisation vidéo : $e');
    }
  }

  void preload(String url) {
    if (!_controllers.containsKey(url)) {
      _initController(url).then((controller) {
        if (!_controllers.containsKey(url)) {
          _controllers[url] = controller;
          _cleanupOldControllers();
        }
      }).catchError((_) {
        // Ignore les erreurs de preload
      });
    }
  }

  void play(String url) {
    _controllers.forEach((key, controller) {
      if (key == url) {
        if (!controller.value.isPlaying && controller.value.isInitialized) {
          controller.play();
        }
      } else {
        if (controller.value.isPlaying) {
          controller.pause();
        }
      }
    });
  }

  void pause(String url) {
    final controller = _controllers[url];
    if (controller != null && controller.value.isInitialized) {
      controller.pause();
    }
  }

  void releaseController(String url) {
    final controller = _controllers[url];
    if (controller != null) {
      controller.dispose();
      _controllers.remove(url);
    }
  }

  void _cleanupOldControllers() {
    if (_controllers.length > _maxCacheCount) {
      final keys = List<String>.from(_controllers.keys)..sort();
      final removeKeys = keys.take(_controllers.length - _maxCacheCount);

      for (final key in removeKeys) {
        _controllers[key]?.dispose();
        _controllers.remove(key);
      }
    }
  }
}
