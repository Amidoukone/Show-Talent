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
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      setState(() {
        _isLoading = true;
        _isError = false;
      });

      final File videoFile = await _getValidVideoFile(widget.videoUrl);

      if (!mounted) return;

      _videoPlayerController = VideoPlayerController.file(videoFile)
        ..initialize().then((_) {
          if (!mounted) return;

          setState(() {
            _chewieController = ChewieController(
              videoPlayerController: _videoPlayerController!,
              autoPlay: true,
              looping: false,
              showControls: true,
              allowFullScreen: true,
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
                    'Erreur lors de la lecture de la vidéo',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              },
            );
            _isLoading = false;
          });
        }).catchError((error) {
          setState(() {
            _isError = true;
            _isLoading = false;
          });
        });

      _videoPlayerController!.addListener(() {
        if (_videoPlayerController!.value.hasError) {
          setState(() {
            _isError = true;
          });
        }
      });
    } catch (error) {
      setState(() {
        _isError = true;
        _isLoading = false;
      });
    }
  }

  Future<File> _getValidVideoFile(String url) async {
    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(url);
      if (fileInfo != null && await fileInfo.file.exists()) {
        return fileInfo.file;
      }
      return await DefaultCacheManager().getSingleFile(url);
    } catch (e) {
      throw Exception('Erreur lors du téléchargement de la vidéo');
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isError || _chewieController == null || !_videoPlayerController!.value.isInitialized) {
      return const Center(
        child: Text(
          'Erreur lors de la lecture de la vidéo',
          style: TextStyle(color: Colors.red, fontSize: 16),
        ),
      );
    }

    return Chewie(controller: _chewieController!);
  }
}
