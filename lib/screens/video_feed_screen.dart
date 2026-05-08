import 'dart:async';

import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
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
  final UserController _userController = Get.find<UserController>();
  final FollowController _followController = Get.find<FollowController>();

  final VideoManager videoManager = VideoManager();
  late final VideoFocusOrchestrator _focusOrchestrator;

  int _currentIndex = 0;
  bool _isActive = true;
  bool _didPauseForEmptyFeed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pageController = PageController(initialPage: 0);

    videoController = FeatureControllerRegistry.ensureVideoController(
      contextKey: widget.contextKey,
      enableLiveStream: false,
      enableFeedFetch: false,
      permanent: true,
    );
    videoController.replaceVideos(widget.videos, selectedIndex: 0);

    _focusOrchestrator = VideoFocusOrchestrator(
      contextKey: widget.contextKey,
      videoManager: videoManager,
      videos: _currentVideos,
      useHlsForVideo: (video) =>
          videoController.preferHlsPlayback && video.hasAdaptiveHlsSource,
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

    unawaited(_focusOrchestrator.onDispose());
    FeatureControllerRegistry.releaseVideoController(widget.contextKey);

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

  void _triggerPageChangeHaptic() {
    unawaited(HapticFeedback.selectionClick().catchError((_) {}));
  }

  Future<void> _handlePageChanged(int index) async {
    if (!mounted || !_isActive) return;

    final videos = _currentVideos;
    if (index < 0 || index >= videos.length) return;

    _currentIndex = index;
    videoController.currentIndex.value = index;

    _focusOrchestrator.updateVideos(videos);
    await _focusOrchestrator.onIndexChanged(index);
  }

  List<Video> get _currentVideos => videoController.videoList.toList();

  void _syncPageWithFeedLength(int length) {
    if (length <= 0) return;

    final clampedIndex = _currentIndex.clamp(0, length - 1).toInt();
    if (clampedIndex == _currentIndex) return;

    _currentIndex = clampedIndex;
    videoController.currentIndex.value = clampedIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;

      final currentPage = _pageController.page?.round() ?? _currentIndex;
      if (currentPage != clampedIndex) {
        _pageController.jumpToPage(clampedIndex);
      }

      unawaited(_handlePageChanged(clampedIndex));
    });
  }

  Widget _buildEmptyFeedState(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.video_library_outlined,
                color: Colors.white70,
                size: 42,
              ),
              const SizedBox(height: 12),
              const Text(
                'Aucune video disponible pour le moment.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Revenez au feed principal pour actualiser la liste.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => Get.back<void>(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                label: const Text(
                  'Retour',
                  style: TextStyle(color: Colors.white),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        final videos = videoController.videoList.toList(growable: false);

        if (videos.isEmpty) {
          if (!_didPauseForEmptyFeed) {
            _didPauseForEmptyFeed = true;
            unawaited(_pauseAllVideos());
          }
          return _buildEmptyFeedState(context);
        }

        _didPauseForEmptyFeed = false;
        _focusOrchestrator.updateVideos(videos);
        _syncPageWithFeedLength(videos.length);

        if (_currentIndex >= videos.length) {
          return const SizedBox.shrink();
        }

        return PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          physics: const VideoPageScrollPhysics(),
          dragStartBehavior: DragStartBehavior.down,
          allowImplicitScrolling: false,
          itemCount: videos.length,
          onPageChanged: (index) {
            if (index < 0 || index >= videos.length) {
              return;
            }
            if (index != _currentIndex) {
              _triggerPageChangeHaptic();
            }
            _currentIndex = index;
            unawaited(_handlePageChanged(index));
          },
          itemBuilder: (context, index) {
            final video = videos[index];
            final player =
                videoManager.getController(widget.contextKey, video.videoUrl);

            return SmartVideoPlayer(
              key: ValueKey(video.id),
              player: player,
              videoController: videoController,
              userController: _userController,
              followController: _followController,
              contextKey: widget.contextKey,
              videoUrl: video.videoUrl,
              video: video,
              currentIndex: index,
              videoList: videos,
              autoPlay: true,
              enableTapToPlay: true,
              showControls: true,
              showProgressBar: true,
            );
          },
        );
      }),
    );
  }
}
