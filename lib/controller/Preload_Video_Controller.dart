import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

class PreloadVideoController {
  final Map<String, VideoPlayerController> _controllers = {};

  Future<VideoPlayerController> getController(String url) async {
    if (_controllers.containsKey(url)) return _controllers[url]!;

    final file = await DefaultCacheManager().getSingleFile(url);
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    controller.setLooping(true);
    _controllers[url] = controller;
    return controller;
  }

  Future<void> preloadVideos(List<String> urls) async {
    for (var url in urls) {
      if (!_controllers.containsKey(url)) {
        try {
          final file = await DefaultCacheManager().getSingleFile(url);
          final controller = VideoPlayerController.file(file);
          await controller.initialize();
          controller.setLooping(true);
          _controllers[url] = controller;
        } catch (_) {}
      }
    }
  }

  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  void pauseAllExcept(String currentUrl) {
    _controllers.forEach((url, controller) {
      if (url == currentUrl) {
        controller.play();
      } else {
        controller.pause();
      }
    });
  }
}
