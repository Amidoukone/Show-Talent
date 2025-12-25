import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/widgets/video_manager.dart';

class VideoFeedScreen extends StatefulWidget {
  final List<Video> videos;
  final String contextKey;

  const VideoFeedScreen({
    super.key,
    required this.videos,
    required this.contextKey,
  });

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> with WidgetsBindingObserver {
  late final PageController _pageController;
  late final VideoController videoController;
  final VideoManager videoManager = VideoManager();

  int _currentIndex = 0;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pageController = PageController(initialPage: 0);

    if (!Get.isRegistered<VideoController>(tag: widget.contextKey)) {
      Get.put(VideoController(contextKey: widget.contextKey), tag: widget.contextKey, permanent: true);
    }
    videoController = Get.find<VideoController>(tag: widget.contextKey);
    videoController.videoList.assignAll(widget.videos);
    videoController.currentIndex.value = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePageChanged(0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    unawaited(videoManager.disposeAllForContext(widget.contextKey));
    super.dispose();
  }

  @override
  void deactivate() {
    _pauseAllVideos();
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isActive = (state == AppLifecycleState.resumed);

    if (_isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handlePageChanged(_currentIndex);
      });
    } else {
      _pauseAllVideos();
    }
  }

  Future<void> _pauseAllVideos() async {
    await videoManager.pauseAll(widget.contextKey);
  }

  Future<void> _handlePageChanged(int index) async {
    if (!mounted || !_isActive) return;

    final videos = videoController.videoList;
    if (index < 0 || index >= videos.length) return;

    final url = videos[index].videoUrl;
    videoController.currentIndex.value = index;

    final urls = videos.map((v) => v.videoUrl).toList();
    videoManager.preloadSurrounding(widget.contextKey, urls, index, activeUrl: url);
    await videoManager.pauseAllExcept(widget.contextKey, url);

    final player = videoManager.getController(widget.contextKey, url);
    final ctrl = player?.controller;

    if (ctrl == null || !ctrl.value.isInitialized || ctrl.value.hasError) {
      try {
        await videoManager.initializeController(
          widget.contextKey,
          url,
          autoPlay: true,
          activeUrl: url,
        );
      } catch (e) {
        debugPrint('❌ Erreur init contrôleur (video_feed): $e');
      }
    } else if (!ctrl.value.isPlaying) {
      try {
        await ctrl.play();
      } catch (_) {}
    }

    _disposeFarPlayers(index);
  }

  Future<void> _disposeFarPlayers(int currentIndex) async {
    const disposeWindow = 20;
    final videos = videoController.videoList;
    final urls = videos.map((v) => v.videoUrl).toList();

    if (videos.length <= disposeWindow) return;

    final start = (currentIndex - disposeWindow ~/ 2).clamp(0, videos.length);
    final end = (start + disposeWindow).clamp(0, videos.length);
    final keepUrls = videos.sublist(start, end).map((v) => v.videoUrl).toSet();
    final allUrls = urls.toSet();
    final toDispose = allUrls.difference(keepUrls).toList();

    if (toDispose.isNotEmpty) {
      await videoManager.disposeUrls(widget.contextKey, toDispose);
    }
  }

  @override
  Widget build(BuildContext context) {
    final videos = videoController.videoList;

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: videos.length,
        onPageChanged: (index) {
          _currentIndex = index;
          _handlePageChanged(index);
        },
        itemBuilder: (context, index) {
          final video = videos[index];
          final player = videoManager.getController(widget.contextKey, video.videoUrl);

          return SmartVideoPlayer(
            key: ValueKey(video.id),
            contextKey: widget.contextKey,
            videoUrl: video.videoUrl,
            video: video,
            player: player,
            currentIndex: index,
            videoList: videos,
            autoPlay: true,
            enableTapToPlay: true,
            showControls: true,
            showProgressBar: true,
          );
        },
      ),
    );
  }
}
