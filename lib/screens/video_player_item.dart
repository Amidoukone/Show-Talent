import 'dart:async';
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

      final File? localFile = await _tryGetCachedFile(widget.videoUrl);

      if (!mounted) return;

      _videoPlayerController = localFile != null
          ? VideoPlayerController.file(localFile)
          : VideoPlayerController.network(widget.videoUrl);

      await _videoPlayerController!.initialize();
      if (!mounted) return;

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
        errorBuilder: (context, errorMessage) => Center(
          child: Text(
            'Erreur vidéo',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );

      setState(() {
        _isLoading = false;
      });

      _videoPlayerController!.addListener(() {
        if (_videoPlayerController!.value.hasError) {
          setState(() {
            _isError = true;
          });
        }
      });
    } catch (e) {
      setState(() {
        _isError = true;
        _isLoading = false;
      });
    }
  }

  Future<File?> _tryGetCachedFile(String url) async {
    try {
      final cache = DefaultCacheManager();
      final fileInfo = await cache.getFileFromCache(url);
      if (fileInfo != null && await fileInfo.file.exists()) {
        return fileInfo.file;
      }

      final file = await cache.getSingleFile(url)
          .timeout(const Duration(seconds: 10), onTimeout: () => throw TimeoutException("Timeout"));
      if (await file.exists()) return file;
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
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
          'Erreur lors de la lecture',
          style: TextStyle(color: Colors.red, fontSize: 16),
        ),
      );
    }

    return Chewie(controller: _chewieController!);
  }
}
