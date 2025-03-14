  import 'package:flutter/material.dart';
  import 'package:video_player/video_player.dart';

  class PreloadedVideoPlayer extends StatefulWidget {
    final String videoUrl;

    const PreloadedVideoPlayer({super.key, required this.videoUrl});

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
        });
    }

    @override
    void dispose() {
      _controller.dispose();
      super.dispose();
    }

    @override
    Widget build(BuildContext context) {
      return _isInitialized
          ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            )
          : CircularProgressIndicator();
    }
  }
