import 'package:video_player/video_player.dart';

class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  final Map<String, VideoPlayerController> _controllers = {};

  factory VideoManager() => _instance;

  VideoManager._internal();

  Future<VideoPlayerController> getController(String url) async {
    if (_controllers.containsKey(url)) {
      return _controllers[url]!;
    }

    final controller = VideoPlayerController.network(url);
    await controller.initialize();
    controller.setLooping(true);
    _controllers[url] = controller;
    return controller;
  }

  void play(String url) {
    for (final entry in _controllers.entries) {
      if (entry.key == url) {
        entry.value.play();
      } else {
        entry.value.pause();
      }
    }
  }

  void pause(String url) {
    if (_controllers.containsKey(url)) {
      _controllers[url]!.pause();
    }
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }
}
