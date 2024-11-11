import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class VideoPlayerItem extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerItem({super.key, required this.videoUrl});

  @override
  State<VideoPlayerItem> createState() => _VideoPlayerItemState();
}

class _VideoPlayerItemState extends State<VideoPlayerItem> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final File videoFile = await DefaultCacheManager().getSingleFile(widget.videoUrl);
      _videoPlayerController = VideoPlayerController.file(videoFile)
        ..initialize().then((_) {
          setState(() {
            _chewieController = ChewieController(
              videoPlayerController: _videoPlayerController,
              autoPlay: true,
              looping: true,
              showControls: true,
              materialProgressColors: ChewieProgressColors(
                playedColor: Colors.red,
                handleColor: Colors.red,
                bufferedColor: Colors.white.withOpacity(0.6),
                backgroundColor: Colors.grey,
              ),
              placeholder: Container(color: Colors.black),
              errorBuilder: (context, errorMessage) {
                return Center(
                  child: Text(
                    'Erreur lors de la lecture de la vidéo: $errorMessage',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              },
            );
          });
        }).catchError((error) {
          setState(() {
            _isError = true;
          });
        });
    } catch (error) {
      setState(() {
        _isError = true;
      });
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  void _setPlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _videoPlayerController.setPlaybackSpeed(speed);
  }

  @override
  Widget build(BuildContext context) {
    if (_isError) {
      return const Center(
        child: Text('Erreur lors de la lecture de la vidéo', style: TextStyle(color: Colors.red)),
      );
    }

    if (_chewieController == null || !_videoPlayerController.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Chewie(controller: _chewieController!),
        ),
        Positioned(
          bottom: 60,
          left: 20,
          child: IconButton(
            icon: Icon(
              _videoPlayerController.value.isPlaying
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
              color: Colors.white,
              size: 40,
            ),
            onPressed: () {
              setState(() {
                _videoPlayerController.value.isPlaying
                    ? _videoPlayerController.pause()
                    : _videoPlayerController.play();
              });
            },
          ),
        ),
        Positioned(
          bottom: 60,
          right: 20,
          child: PopupMenuButton<double>(
            initialValue: _playbackSpeed,
            onSelected: (speed) {
              _setPlaybackSpeed(speed);
            },
            color: Colors.white,
            child: const Icon(Icons.speed, color: Colors.white, size: 30),
            itemBuilder: (context) => [0.5, 1.0, 1.5, 2.0].map((speed) {
              return PopupMenuItem(
                value: speed,
                child: Text(
                  "${speed}x",
                  style: const TextStyle(color: Colors.black),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
