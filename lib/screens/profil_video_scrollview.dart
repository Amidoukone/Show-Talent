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

    // Which video the user is on, by identity rather than by position.
    //
    // `ProfileController` keeps its list to 25 entries and drops the excess
    // from the *front* (`_videoMemoryLimit`), so the page that adds twenty
    // videos also removes fifteen. Every index into the old list is then off
    // by fifteen, and handing the old index back moved the user fifteen
    // videos forward from the one they were watching. Only an id survives a
    // window that slides.
    final before = _currentVideos;
    final anchorIndex = before.isEmpty
        ? 0
        : _pager.currentIndex.clamp(0, before.length - 1).toInt();
    final anchorId = before.isEmpty ? null : before[anchorIndex].id;

    await profileController.fetchUserVideos(widget.uid);
    if (_isDisposed || !mounted) return;

    // The profile's list is refreshed by a fetch, not by the deletion, so it
    // still holds anything deleted from the player since this screen opened.
    // Handing those back would put a document that no longer exists in front
    // of the user, with a URL that no longer resolves.
    profileController.removeVideosLocally(_vc.deletedVideoIds);

    final playable = profileController.videoList
        .where((video) => video.isPlayable)
        .toList(growable: false);
    if (playable.isEmpty) return;

    // Same videos in the same order: the page brought nothing this screen can
    // use, and replacing the list would only churn the tiles.
    final beforeIds = before.map((video) => video.id).toList(growable: false);
    final afterIds = playable.map((video) => video.id).toList(growable: false);
    if (beforeIds.length == afterIds.length) {
      var identical = true;
      for (var i = 0; i < afterIds.length; i++) {
        if (beforeIds[i] != afterIds[i]) {
          identical = false;
          break;
        }
      }
      if (identical) return;
    }

    final foundAt = anchorId == null
        ? -1
        : playable.indexWhere((video) => video.id == anchorId);
    final nextIndex = foundAt >= 0
        ? foundAt
        : anchorIndex.clamp(0, playable.length - 1).toInt();

    _vc.replaceVideos(playable, selectedIndex: nextIndex);

    // The page view does not follow `currentIndex` on its own. Left behind,
    // it would show one video while every tile believed a different one was
    // active — so nothing would play at all.
    if (nextIndex == anchorIndex) return;

    await WidgetsBinding.instance.endOfFrame;
    if (_isDisposed || !mounted) return;

    _pager.jumpToPage(nextIndex);
    await _pager.activate(nextIndex);
  }

  Future<void> _safeExit() async {
    if (_isDisposed || _isExiting) return;

    setState(() => _isExiting = true);

    // The grid the user is going back to reads its own list. Anything deleted
    // in here has to leave that list too, or the profile shows a video that
    // no longer exists until something else refreshes it.
    if (Get.isRegistered<ProfileController>(tag: widget.uid)) {
      Get.find<ProfileController>(
        tag: widget.uid,
      ).removeVideosLocally(_vc.deletedVideoIds);
    }

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
