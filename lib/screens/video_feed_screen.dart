import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/videos/domain/video_focus_orchestrator.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:adfoot/widgets/video_page_scroll_physics.dart';

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

class _VideoFeedScreenState extends State<VideoFeedScreen>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  late final VideoController videoController;

  final VideoManager videoManager = VideoManager();
  late final VideoFocusOrchestrator _focusOrchestrator;

  int _currentIndex = 0;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pageController = PageController(initialPage: 0);

    // ✅ GetX controller (taggé par contextKey)
    if (!Get.isRegistered<VideoController>(tag: widget.contextKey)) {
      Get.put(
        VideoController(contextKey: widget.contextKey),
        tag: widget.contextKey,
        permanent: true,
      );
    }

    videoController = Get.find<VideoController>(tag: widget.contextKey);
    videoController.videoList.assignAll(widget.videos);
    videoController.currentIndex.value = 0;

    // ✅ Orchestrateur de focus (préload/pause/dispose window)
    _focusOrchestrator = VideoFocusOrchestrator(
      contextKey: widget.contextKey,
      videoManager: videoManager,
      videos: _currentVideos,
      disposeWindow: 20,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handlePageChanged(0));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();

    // ✅ Un seul point de sortie (pause + dispose contexte)
    unawaited(_focusOrchestrator.onDispose());

    super.dispose();
  }

  @override
  void deactivate() {
    unawaited(_pauseAllVideos());
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isActive = (state == AppLifecycleState.resumed);

    if (_isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_handlePageChanged(_currentIndex));
      });
    } else {
      unawaited(_pauseAllVideos());
    }
  }

  Future<void> _pauseAllVideos() async {
    await videoManager.pauseAll(widget.contextKey);
  }

  Future<void> _handlePageChanged(int index) async {
    if (!mounted || !_isActive) return;

    final videos = videoController.videoList;
    if (index < 0 || index >= videos.length) return;

    _currentIndex = index;
    videoController.currentIndex.value = index;

    // ✅ Assure que l’orchestrateur a la liste à jour
    _focusOrchestrator.updateVideos(_currentVideos);

    // ✅ Orchestration centralisée (préload/pause/init/play/dispose window)
    await _focusOrchestrator.onIndexChanged(index);
  }

  /// Copie défensive: évite les effets de bord si la RxList change pendant le scroll
  List<Video> get _currentVideos => videoController.videoList.toList();

  @override
  Widget build(BuildContext context) {
    final videos = videoController.videoList;

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        physics: const VideoPageScrollPhysics(),
        dragStartBehavior: DragStartBehavior.down,
        allowImplicitScrolling: true,
        itemCount: videos.length,
        onPageChanged: (index) {
          _currentIndex = index;
          unawaited(_handlePageChanged(index));
        },
        itemBuilder: (context, index) {
          final video = videos[index];
          final player =
              videoManager.getController(widget.contextKey, video.videoUrl);

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
