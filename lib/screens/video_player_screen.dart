import 'package:adfoot/models/video.dart';
import 'package:flutter/material.dart';
import 'package:adfoot/screens/video_player_item.dart';

class VideoPlayerScreen extends StatelessWidget {
  final String videoUrl;

  const VideoPlayerScreen({super.key, required this.videoUrl, required Video video});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vidéo'),
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: Center(
        child: VideoPlayerItem(videoUrl: videoUrl),
      ),
    );
  }
}
