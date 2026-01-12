import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/profile_controller.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/videos/domain/video_focus_orchestrator.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:adfoot/widgets/video_page_scroll_physics.dart';

class ProfileVideoFeedScreen extends StatefulWidget {
  final String uid;

  const ProfileVideoFeedScreen({super.key, required this.uid});

  @override
  State<ProfileVideoFeedScreen> createState() => _ProfileVideoFeedScreenState();
}

class _ProfileVideoFeedScreenState extends State<ProfileVideoFeedScreen>
    with WidgetsBindingObserver {
  late final ProfileController _profileController;
  late final VideoController _videoController;
  late final PageController _pageController;

  final VideoManager _videoManager = VideoManager();
  late final VideoFocusOrchestrator _focusOrchestrator;

  int _currentIndex = 0;
  bool _isDisposed = false;

  String get _ctxKey => 'profile:${widget.uid}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _profileController = Get.find<ProfileController>(tag: widget.uid);

    _videoController = Get.isRegistered<VideoController>(tag: _ctxKey)
        ? Get.find<VideoController>(tag: _ctxKey)
        : Get.put(
            VideoController(contextKey: _ctxKey),
            tag: _ctxKey,
            permanent: true,
          );

    _pageController = PageController(initialPage: _currentIndex);

    // Initialisation de la liste des vidéos depuis le profil
    final vids = _profileController.videoList.toList();
    _videoController.videoList.assignAll(vids);
    _videoController.currentIndex.value = 0;

    // ✅ Orchestrateur de focus (préload/pause/init/play/dispose window)
    _focusOrchestrator = VideoFocusOrchestrator(
      contextKey: _ctxKey,
      videoManager: _videoManager,
      videos: _currentVideos,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        unawaited(_handleIndexChange(0));
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();

    // ✅ Un seul point de sortie (pause + dispose contexte)
    unawaited(_focusOrchestrator.onDispose());

    if (Get.isRegistered<VideoController>(tag: _ctxKey)) {
      Get.delete<VideoController>(tag: _ctxKey);
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Pause immédiate (sécurité)
      unawaited(_videoManager.pauseAll(_ctxKey));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_resumeCurrentVideo());
    }
  }

  Future<void> _resumeCurrentVideo() async {
    if (_isDisposed) return;

    // ✅ Reprend via orchestrateur (relance preload/pauseExcept/init/play)
    _focusOrchestrator.updateVideos(_currentVideos);
    await _focusOrchestrator.onIndexChanged(_currentIndex);
  }

  Future<void> _handleIndexChange(int idx) async {
    if (_isDisposed) return;

    final vids = _videoController.videoList.toList();
    if (idx < 0 || idx >= vids.length) return;

    _currentIndex = idx;
    _videoController.currentIndex.value = idx;

    // ✅ Orchestration centralisée
    _focusOrchestrator.updateVideos(_currentVideos);
    await _focusOrchestrator.onIndexChanged(idx);
  }

  /// Copie défensive : évite les effets de bord si la RxList change pendant le scroll
  List<Video> get _currentVideos => _videoController.videoList.toList();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final videos = _videoController.videoList;

      if (videos.isEmpty) {
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Text(
              'Aucune vidéo à afficher',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }

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
            if (!_isDisposed) {
              unawaited(_handleIndexChange(index));
            }
          },
          itemBuilder: (context, index) {
            final vid = videos[index];
            final player = _videoManager.getController(_ctxKey, vid.videoUrl);

            return Stack(
              fit: StackFit.expand,
              children: [
                SmartVideoPlayer(
                  key: ValueKey(vid.id),
                  contextKey: _ctxKey,
                  videoUrl: vid.videoUrl,
                  video: vid,
                  player: player,
                  currentIndex: index,
                  videoList: videos,
                  autoPlay: true,
                  enableTapToPlay: true,
                  showControls: true,
                  showProgressBar: true,
                ),
                Positioned(
                  bottom: 100,
                  left: 12,
                  right: 80,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vid.description.trim().isNotEmpty
                            ? vid.description.trim()
                            : 'Pas de description',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              offset: Offset(1, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        vid.caption.trim().isNotEmpty
                            ? vid.caption.trim()
                            : 'Pas de légende',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              offset: Offset(1, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    });
  }
}
