import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

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

  @override
  void initState() {
    super.initState();

    // Initialiser le VideoPlayerController avec l'URL de la vidéo
    _videoPlayerController = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {
          _chewieController = ChewieController(
            videoPlayerController: _videoPlayerController,
            autoPlay: true,
            looping: true,
            showControls: true,
            allowPlaybackSpeedChanging: true,
            allowMuting: true,
            // Modifier les contrôles avec des tailles personnalisées
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
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
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

    return Container(
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.center,
        child: SizedBox(
          width: _videoPlayerController.value.size.width,
          height: _videoPlayerController.value.size.height,
          child: Chewie(controller: _chewieController!),
        ),
      ),
    );
  }
}
