import 'dart:async';

import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/profile_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
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
  final UserController _userController = Get.find<UserController>();
  final FollowController _followController = Get.find<FollowController>();

  final VideoManager _videoManager = VideoManager();
  late final VideoFocusOrchestrator _focusOrchestrator;

  int _currentIndex = 0;
  bool _isDisposed = false;

  String get _ctxKey => 'profile:${widget.uid}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _profileController =
        FeatureControllerRegistry.ensureProfileController(widget.uid);

    _videoController = FeatureControllerRegistry.ensureVideoController(
      contextKey: _ctxKey,
      enableLiveStream: false,
      enableFeedFetch: false,
      permanent: true,
    );

    _pageController = PageController(initialPage: _currentIndex);

    // Initialisation de la liste des vidéos depuis le profil
    final vids = _profileController.videoList.toList();
    _videoController.replaceVideos(vids, selectedIndex: 0);

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

    FeatureControllerRegistry.releaseVideoController(_ctxKey);

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

    final vids = _currentVideos;
    if (idx < 0 || idx >= vids.length) return;

    _currentIndex = idx;
    _videoController.currentIndex.value = idx;

    // ✅ Orchestration centralisée
    _focusOrchestrator.updateVideos(_currentVideos);
    await _focusOrchestrator.onIndexChanged(idx);
  }

  void _triggerPageChangeHaptic() {
    unawaited(HapticFeedback.selectionClick().catchError((_) {}));
  }

  /// Copie défensive : évite les effets de bord si la RxList change pendant le scroll
  List<Video> get _currentVideos =>
      _videoController.videoList.toList(growable: false);

  void _syncPageWithFeedLength(int length) {
    if (length <= 0) return;

    final clampedIndex = _currentIndex.clamp(0, length - 1).toInt();
    if (clampedIndex == _currentIndex) return;

    _currentIndex = clampedIndex;
    _videoController.currentIndex.value = clampedIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed || !_pageController.hasClients) return;

      final currentPage = _pageController.page?.round() ?? _currentIndex;
      if (currentPage != clampedIndex) {
        _pageController.jumpToPage(clampedIndex);
      }

      unawaited(_handleIndexChange(clampedIndex));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final videos = _currentVideos;

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

      _syncPageWithFeedLength(videos.length);
      if (_currentIndex >= videos.length) {
        return const SizedBox.shrink();
      }

      return Scaffold(
        backgroundColor: Colors.black,
        body: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          physics: const VideoPageScrollPhysics(),
          dragStartBehavior: DragStartBehavior.down,
          allowImplicitScrolling: false,
          itemCount: videos.length,
          onPageChanged: (index) {
            if (index < 0 || index >= videos.length) return;
            if (!_isDisposed) {
              if (index != _currentIndex) {
                _triggerPageChangeHaptic();
              }
              unawaited(_handleIndexChange(index));
            }
          },
          itemBuilder: (context, index) {
            final vid = videos[index];
            final player = _videoManager.getController(_ctxKey, vid.videoUrl);

            return SmartVideoPlayer(
              key: ValueKey(vid.id),
              player: player,
              videoController: _videoController,
              userController: _userController,
              followController: _followController,
              contextKey: _ctxKey,
              videoUrl: vid.videoUrl,
              video: vid,
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
    });
  }
}
