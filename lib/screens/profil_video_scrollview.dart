import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:adfoot/controller/video_controller.dart';

class ProfileVideoScrollView extends StatefulWidget {
  final List<Video> videos;
  final int initialIndex;
  final String uid;
  final String contextKey;

  const ProfileVideoScrollView({
    super.key,
    required this.videos,
    required this.initialIndex,
    required this.uid,
    required this.contextKey,
  });

  @override
  State<ProfileVideoScrollView> createState() => _ProfileVideoScrollViewState();
}

class _ProfileVideoScrollViewState extends State<ProfileVideoScrollView> {
  late final PageController _pageController;
  late int _currentIndex;
  late final String _ctxKey;
  final VideoManager _videoManager = VideoManager();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _ctxKey = widget.contextKey;
    _pageController = PageController(initialPage: _currentIndex);

    if (!Get.isRegistered<VideoController>(tag: _ctxKey)) {
      Get.put(VideoController(contextKey: _ctxKey), tag: _ctxKey, permanent: true);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processIndex(_currentIndex);
    });
  }

  void _processIndex(int idx) {
    final urls = widget.videos.map((v) => v.videoUrl).toList();
    final currentUrl = urls[idx];

    _videoManager.preloadSurrounding(_ctxKey, urls, idx);
    _videoManager.pauseAllExcept(_ctxKey, currentUrl);

    if (!_videoManager.hasController(_ctxKey, currentUrl)) {
      unawaited(_videoManager.initializeController(_ctxKey, currentUrl));
    }
  }

  @override
  void dispose() {
    _videoManager.disposeAllForContext(_ctxKey);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videos.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Aucune vidéo publiée',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: widget.videos.length,
            onPageChanged: (idx) {
              setState(() => _currentIndex = idx);
              _processIndex(idx);
            },
            itemBuilder: (_, idx) {
              final video = widget.videos[idx];
              final controller = _videoManager.getController(_ctxKey, video.videoUrl);

              return Stack(
                children: [
                  SmartVideoPlayer(
                    key: ValueKey(video.id),
                    contextKey: _ctxKey,
                    videoUrl: video.videoUrl,
                    video: video,
                    currentIndex: idx,
                    videoList: widget.videos,
                    enableTapToPlay: true,
                    autoPlay: true,
                    showControls: true,
                    showProgressBar: true,
                    controller: controller,
                  ),
                  Positioned(
                    bottom: 100,
                    left: 10,
                    right: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.songName.isNotEmpty ? video.songName : 'Musique inconnue',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2)],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          video.caption.isNotEmpty ? video.caption : 'Pas de légende',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2)],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                  onPressed: () async {
                    await _videoManager.pauseAll(_ctxKey);
                    if (mounted) {
                      Get.back();
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
