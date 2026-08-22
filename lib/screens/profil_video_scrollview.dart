import 'dart:async';

import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/profile_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/immersive_video_chrome.dart';
import 'package:adfoot/widgets/video_feed_pager.dart';
import 'package:adfoot/videos/video_manager.dart';
import 'package:adfoot/controller/video_controller.dart';

/// A profile's videos, full screen.
///
/// Everything that makes a vertical video feed work — the page controller,
/// the index bookkeeping, the focus orchestrator, the lifecycle pausing, the
/// haptics — now lives in [VideoFeedPager]. This screen is the part that is
/// actually about *a profile*: which videos, how to leave, and where the next
/// page comes from.
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
  late final VideoController _vc;
  final UserController _userController = Get.find<UserController>();
  final FollowController _followController = Get.find<FollowController>();
  final VideoFeedPagerController _pager = VideoFeedPagerController();
  final VideoManager _videoManager = VideoManager();

  bool _isDisposed = false;
  bool _isExiting = false;

  static const int _videoSlidingWindowLimit = 25;

  @override
  void initState() {
    super.initState();

    _vc = FeatureControllerRegistry.ensureVideoController(
      contextKey: widget.contextKey,
      enableLiveStream: false,
      enableFeedFetch: false,
      permanent: true,
    );
    _vc.replaceVideos(widget.videos, selectedIndex: widget.initialIndex);
  }

  @override
  void dispose() {
    _isDisposed = true;
    FeatureControllerRegistry.releaseVideoController(widget.contextKey);
    super.dispose();
  }

  List<Video> get _currentVideos => _vc.videoList.toList(growable: false);

  /// Loads the next page of this profile's videos as the user reaches the end.
  ///
  /// This screen used to receive a fixed snapshot of whatever the profile grid
  /// had loaded when it was opened, and scroll to the end of it — full stop.
  /// The pagination existed all along on [ProfileController]; nothing was
  /// wired to it, because only the home feed had a "load more" hook and there
  /// was no shared feed to put one in.
  Future<void> _loadMoreProfileVideos() async {
    if (_isDisposed || _isExiting) return;
    if (!Get.isRegistered<ProfileController>(tag: widget.uid)) return;

    final profileController = Get.find<ProfileController>(tag: widget.uid);
    if (!profileController.hasMoreVideos || profileController.isLoadingVideos) {
      return;
    }

    await profileController.fetchUserVideos(widget.uid);
    if (_isDisposed || !mounted) return;

    final playable = profileController.videoList
        .where((video) => video.isPlayable)
        .toList(growable: false);
    if (playable.length <= _currentVideos.length) return;

    _vc.replaceVideos(playable, selectedIndex: _pager.currentIndex);
  }

  Future<void> _safeExit() async {
    if (_isDisposed || _isExiting) return;

    setState(() => _isExiting = true);

    try {
      _vc.currentIndex.value = -1;
    } catch (_) {}

    await _videoManager.pauseAll(widget.contextKey);
    await WidgetsBinding.instance.endOfFrame;

    if (!_isDisposed && mounted) {
      Get.back();
    }
  }

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
        body: Obx(() {
          final videos = _currentVideos;

          return Stack(
            children: [
              if (_isExiting)
                const SizedBox.expand(child: ColoredBox(color: Colors.black))
              else if (videos.isEmpty)
                ImmersiveVideoEmptyState(
                  icon: Icons.video_library_outlined,
                  title: VideoUiStrings.emptyProfileVideoFeedTitle,
                  message: VideoUiStrings.emptyProfileVideoFeedMessage,
                  actionLabel: VideoUiStrings.back,
                  onAction: () => unawaited(_safeExit()),
                )
              else
                Positioned.fill(
                  child: VideoFeedPager(
                    pagerController: _pager,
                    contextKey: widget.contextKey,
                    videos: videos,
                    videoController: _vc,
                    userController: _userController,
                    followController: _followController,
                    initialIndex: widget.initialIndex,
                    disposeWindow: _videoSlidingWindowLimit,
                    showProfileAction: false,
                    onRequestMore: _loadMoreProfileVideos,
                  ),
                ),
              if (!_isExiting && videos.isNotEmpty)
                ImmersiveVideoBackButton(
                  onPressed: () => unawaited(_safeExit()),
                ),
            ],
          );
        }),
      ),
    );
  }
}
