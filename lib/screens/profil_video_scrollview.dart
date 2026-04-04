import 'dart:async';

import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:adfoot/widgets/video_page_scroll_physics.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/videos/domain/video_focus_orchestrator.dart';

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

class _ProfileVideoScrollViewState extends State<ProfileVideoScrollView>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  late final VideoController _vc;
  final UserController _userController = Get.find<UserController>();
  final FollowController _followController = Get.find<FollowController>();

  final VideoManager _videoManager = VideoManager();
  late final VideoFocusOrchestrator _focusOrchestrator;

  late int _currentIndex;
  bool _isDisposed = false;
  bool _isExiting = false;

  static const int _videoSlidingWindowLimit = 25;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    _vc = FeatureControllerRegistry.ensureVideoController(
      contextKey: widget.contextKey,
      enableLiveStream: false,
      enableFeedFetch: false,
      permanent: true,
    );
    _vc.replaceVideos(widget.videos, selectedIndex: _currentIndex);

    // ✅ Orchestrateur (préload/pause/init/play/dispose window)
    _focusOrchestrator = VideoFocusOrchestrator(
      contextKey: widget.contextKey,
      videoManager: _videoManager,
      videos: _currentVideos,
      useHlsForVideo: (video) =>
          _vc.preferHlsPlayback && video.hasAdaptiveHlsSource,
      disposeWindow: _videoSlidingWindowLimit,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed && !_isExiting) {
        unawaited(_handleIndexChange(_currentIndex));
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    _pageController.dispose();

    // Nettoyage centralisé (pause + dispose contexte)
    unawaited(_focusOrchestrator.onDispose());

    FeatureControllerRegistry.releaseVideoController(widget.contextKey);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || _isExiting) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_videoManager.pauseAll(widget.contextKey));
    }
  }

  // ---------------------------------------------------------------------------
  // Safe exit (anti-crash / anti-VideoPlayer orphan)
  // ---------------------------------------------------------------------------

  Future<void> _safeExit() async {
    if (_isDisposed || _isExiting) return;

    setState(() => _isExiting = true);

    try {
      _vc.currentIndex.value = -1;
    } catch (_) {}

    await _videoManager.pauseAll(widget.contextKey);

    // Laisser Flutter retirer les VideoPlayer de l’arbre
    await WidgetsBinding.instance.endOfFrame;

    if (!_isDisposed && mounted) {
      Get.back();
    }
  }

  // ---------------------------------------------------------------------------
  // Index change (orchestré)
  // ---------------------------------------------------------------------------

  Future<void> _handleIndexChange(int idx) async {
    if (_isDisposed || _isExiting) return;
    if (idx < 0 || idx >= widget.videos.length) return;

    _currentIndex = idx;
    _vc.currentIndex.value = idx;

    // ✅ Assure que l’orchestrateur a la liste à jour
    _focusOrchestrator.updateVideos(_currentVideos);

    // ✅ Orchestration centralisée (préload/pause/init/play/dispose window)
    await _focusOrchestrator.onIndexChanged(idx);

    if (mounted) setState(() {});
  }

  void _triggerPageChangeHaptic() {
    unawaited(HapticFeedback.selectionClick().catchError((_) {}));
  }

  /// Copie défensive : évite les effets de bord si la liste change en amont
  List<Video> get _currentVideos => List.of(widget.videos);

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_safeExit());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Pendant EXIT → aucun VideoPlayer monté
            if (_isExiting)
              const SizedBox.expand(
                child: ColoredBox(color: Colors.black),
              )
            else
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                physics: const VideoPageScrollPhysics(),
                dragStartBehavior: DragStartBehavior.down,
                allowImplicitScrolling: false,
                itemCount: widget.videos.length,
                onPageChanged: (idx) {
                  if (idx != _currentIndex) {
                    _triggerPageChangeHaptic();
                  }
                  unawaited(_handleIndexChange(idx));
                },
                itemBuilder: (_, idx) {
                  final video = widget.videos[idx];
                  final player = _videoManager.getController(
                    widget.contextKey,
                    video.videoUrl,
                  );

                  return SmartVideoPlayer(
                    key: ValueKey(video.id),
                    player: player,
                    videoController: _vc,
                    userController: _userController,
                    followController: _followController,
                    contextKey: widget.contextKey,
                    videoUrl: video.videoUrl,
                    video: video,
                    currentIndex: idx,
                    videoList: widget.videos,
                    enableTapToPlay: true,
                    autoPlay: true,
                    showControls: true,
                    showProgressBar: true,
                    showProfileAction: false,
                  );
                },
              ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 30,
                  ),
                  onPressed: _isExiting ? null : _safeExit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
