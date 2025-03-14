import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PreloadedVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String thumbnailUrl;

  const PreloadedVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
  });

  @override
  _PreloadedVideoPlayerState createState() => _PreloadedVideoPlayerState();
}

class _PreloadedVideoPlayerState extends State<PreloadedVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
        });
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Miniature visible tant que la vidéo n’est pas prête
        if (!_isInitialized)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              widget.thumbnailUrl,
              fit: BoxFit.cover,
            ),
          ),
        // Vidéo visible une fois initialisée
        if (_isInitialized)
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
      ],
    );
  }
}
