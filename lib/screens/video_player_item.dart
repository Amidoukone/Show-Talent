import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart'; // Pour des contrôles vidéo améliorés

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

    // Log de l'URL de la vidéo
    print("Tentative de lecture de la vidéo : ${widget.videoUrl}");

    // Initialiser le VideoPlayerController avec l'URL de la vidéo
    _videoPlayerController = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        print("La vidéo a été initialisée correctement.");
        setState(() {
          _chewieController = ChewieController(
            videoPlayerController: _videoPlayerController,
            autoPlay: true,
            looping: true,
            aspectRatio: _videoPlayerController.value.aspectRatio,
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
        print("Erreur lors de l'initialisation de la vidéo : $error");
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
      return const Center(child: CircularProgressIndicator()); // Affiche un indicateur de chargement
    }

    return AspectRatio(
      aspectRatio: _videoPlayerController.value.aspectRatio,  // Assurez-vous que l'AspectRatio est bien défini
      child: Chewie(
        controller: _chewieController!,
      ),
    );
  }
}
