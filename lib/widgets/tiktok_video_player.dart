import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class TikTokVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const TikTokVideoPlayer({super.key, required this.videoUrl});

  @override
  _TikTokVideoPlayerState createState() => _TikTokVideoPlayerState();
}

class _TikTokVideoPlayerState extends State<TikTokVideoPlayer> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    // Utilisation de `VideoPlayerController.networkUrl` à la place de `network`
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() {});  // Rebuild pour initialiser la vidéo
        _controller.play();  // Lecture automatique
        _controller.setLooping(true);  // Boucler la vidéo
      });
  }

  @override
  void dispose() {
    _controller.dispose();  // Libérer les ressources
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          )
        : const Center(
            child: CircularProgressIndicator(),  // Indicateur de chargement
          );
  }
}
