// UPDATED VideoManager to strictly support only .m3u8 HLS sources
import 'package:video_player/video_player.dart';

class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  final Map<String, VideoPlayerController> _controllers = {};
  static const int _maxCacheCount = 5;

  factory VideoManager() => _instance;

  VideoManager._internal();

  Future<VideoPlayerController> getController(String url) async {
    if (!_isHlsUrl(url)) {
      throw Exception('Seuls les fichiers HLS (.m3u8) sont supportés.');
    }

    if (_controllers.containsKey(url)) {
      final controller = _controllers[url]!;
      if (controller.value.isInitialized) {
        return controller;
      } else {
        try {
          await controller.initialize();
          return controller;
        } catch (e) {
          controller.dispose();
          _controllers.remove(url);
          return _initControllerAndCache(url);
        }
      }
    }

    return _initControllerAndCache(url);
  }

  Future<VideoPlayerController> _initControllerAndCache(String url) async {
    final controller = await _initController(url);
    _controllers[url] = controller;
    _cleanupOldControllers();
    return controller;
  }

  Future<VideoPlayerController> _initController(String url) async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(1.0);
      return controller;
    } catch (e) {
      throw Exception('Erreur initialisation HLS : $e');
    }
  }

  void preload(String url) {
    if (_isHlsUrl(url) && !_controllers.containsKey(url)) {
      _initControllerAndCache(url).then((controller) {
        if (!_controllers.containsKey(url)) {
          _controllers[url] = controller;
          _cleanupOldControllers();
        }
      }).catchError((_) {
        // Ignorer les erreurs de préchargement
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
      final keys = List<String>.from(_controllers.keys);
      final excess = _controllers.length - _maxCacheCount;

      for (int i = 0; i < excess; i++) {
        final key = keys[i];
        _controllers[key]?.dispose();
        _controllers.remove(key);
      }
    }
  }

  bool _isHlsUrl(String url) {
    return url.toLowerCase().endsWith('.m3u8');
  }
}
