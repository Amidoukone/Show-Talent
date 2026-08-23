import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/videos/domain/video_focus_orchestrator.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/videos/video_manager.dart';
import 'package:adfoot/widgets/video_page_scroll_physics.dart';

/// Called when the pager is about to focus [index].
///
/// Return `false` to take the move over — the pager will not focus anything,
/// leaving the host free to jump somewhere else instead.
typedef VideoFeedIndexGuard =
    Future<bool> Function(int index, {required int previousIndex});

/// Called once [index] has been focused and its controller attached.
typedef VideoFeedIndexCallback = Future<void> Function(int index);

/// Drives one vertical video feed from outside its widget.
///
/// Hosts need to move the feed for reasons the feed knows nothing about: a
/// notification pointing at a video, a search being cleared, a batch of live
/// videos arriving at the top.
class VideoFeedPagerController {
  _VideoFeedPagerState? _state;

  /// An index asked for while no pager was listening.
  ///
  /// Every one of these calls used to be a silent no-op when `_state` was
  /// null, and null is the normal state at exactly the moments that matter:
  /// the feed has just gone from empty to loaded, an upload has sent the app
  /// back to the home route, a search has been cleared. The host asks for an
  /// index from a post-frame callback, the pager is only built on the frame
  /// after that, and the request vanished.
  ///
  /// What the user saw was every tile spinning forever: nothing had focused,
  /// so no controller was ever attached — while `videoController.currentIndex`
  /// said a different page was current, so the visible tile believed it was
  /// not the active one and refused to play. Relaunching the app "fixed" it
  /// because the first swipe went through `onPageChanged`, which never
  /// depended on this.
  int? _pendingIndex;

  void _attach(_VideoFeedPagerState state) {
    _state = state;

    final pending = _pendingIndex;
    _pendingIndex = null;
    if (pending != null) {
      state._applyPendingIndex(pending);
    }
  }

  void _detach(_VideoFeedPagerState state) {
    if (identical(_state, state)) _state = null;
  }

  bool get isAttached => _state != null;

  int get currentIndex => _state?._currentIndex ?? _pendingIndex ?? 0;

  /// Moves to [index] without reporting it as a page change.
  ///
  /// A programmatic jump must not be mistaken for the user swiping: that
  /// double-fired the focus work and, on the home feed, could re-trigger the
  /// very "new videos at the top" flow that had just performed the jump.
  void jumpToPage(int index) {
    final state = _state;
    if (state == null) {
      _pendingIndex = index;
      return;
    }
    state._jumpToPage(index);
  }

  /// Focuses [index]: pauses the others, attaches its controller, preloads
  /// its neighbours.
  Future<void> activate(int index) async {
    final state = _state;
    if (state == null) {
      _pendingIndex = index;
      return;
    }
    await state._focus(index);
  }
}

/// The one vertical video feed.
///
/// There were three implementations of this widget — `home_screen.dart`,
/// `profil_video_scrollview.dart` and a `video_feed_screen.dart` that nothing
/// opened — each with its own `PageController`, index bookkeeping, haptics,
/// orchestrator wiring, lifecycle pausing and empty state. They drifted, as
/// three copies do, and the drift was invisible because each one worked:
/// only the home feed ever loaded more videos as you scrolled, and only the
/// home feed prefetched thumbnails. A profile's video feed simply stopped at
/// whatever had been loaded when it was opened.
class VideoFeedPager extends StatefulWidget {
  const VideoFeedPager({
    super.key,
    required this.pagerController,
    required this.contextKey,
    required this.videos,
    required this.videoController,
    required this.userController,
    required this.followController,
    this.initialIndex = 0,
    this.onBeforeIndexChanged,
    this.onIndexFocused,
    this.onRequestMore,
    this.onRefreshRequested,
    this.showDeleteAction = true,
    this.showProfileAction = true,
    this.disposeWindow = 25,
  });

  final VideoFeedPagerController pagerController;
  final String contextKey;
  final List<Video> videos;
  final VideoController videoController;
  final UserController userController;
  final FollowController followController;
  final int initialIndex;
  final VideoFeedIndexGuard? onBeforeIndexChanged;
  final VideoFeedIndexCallback? onIndexFocused;
  final Future<void> Function()? onRequestMore;
  final Future<bool> Function()? onRefreshRequested;
  final bool showDeleteAction;
  final bool showProfileAction;
  final int disposeWindow;

  @override
  State<VideoFeedPager> createState() => _VideoFeedPagerState();
}

class _VideoFeedPagerState extends State<VideoFeedPager>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  late final VideoFocusOrchestrator _orchestrator;
  final VideoManager _videoManager = VideoManager();

  int _currentIndex = 0;
  int? _silencedPageIndex;
  bool _isActive = true;

  /// False until [initState] has built [_pageController].
  ///
  /// [_attach] runs from inside `initState`, so a replayed request can arrive
  /// before there is any page view to move.
  bool _hasPageController = false;

  /// Whether any index has been focused yet, from any caller.
  ///
  /// Read only by the opening focus in [initState], which is a fallback for
  /// hosts that do not ask for an index themselves — not a second request.
  bool _hasFocusedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentIndex = widget.initialIndex
        .clamp(0, widget.videos.isEmpty ? 0 : widget.videos.length - 1)
        .toInt();

    _orchestrator = VideoFocusOrchestrator(
      contextKey: widget.contextKey,
      videoManager: _videoManager,
      videos: widget.videos,
      disposeWindow: widget.disposeWindow,
      onRequestMore: widget.onRequestMore,
    );

    // Attached *before* the page controller exists, so a pending index becomes
    // the page we open on rather than a jump away from one we have already
    // been built on. See [_applyPendingIndex].
    widget.pagerController._attach(this);

    _pageController = PageController(initialPage: _currentIndex);
    _hasPageController = true;

    // Focus what we opened on, unless something already has. The three screens
    // each used to do this from their own initState; when the page view moved
    // in here, the profile feed lost it entirely and opened on a video that
    // never initialised.
    //
    // The home feed still asks for its opening index itself, from a post-frame
    // callback registered while this widget was being built — so it is the
    // *earlier* callback, and both fire on the same frame. Two focus requests
    // 0 ms apart land inside the orchestrator's 120 ms settle window: the
    // first is discarded as stale after it has already paused the context, and
    // the second waits out a delay meant to absorb a fling. That is a cold
    // start paying for a scroll nobody made.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasFocusedOnce) return;
      unawaited(_focus(_currentIndex));
    });
  }

  /// Replays an index that was asked for while no pager was listening.
  ///
  /// Before the page controller exists this only moves the opening index, and
  /// that is the whole point. Replaying it as a `_jumpToPage` instead put the
  /// fault straight back: with no clients, `_jumpToPage` moves `_currentIndex`
  /// and returns, while `_pageController` keeps the `initialPage` it was
  /// constructed with. The feed would then open on one video while
  /// `_currentIndex` and `videoController.currentIndex` named another — the
  /// same mismatch that made every tile spin, reachable whenever the pending
  /// index is not [VideoFeedPager.initialIndex]: a feed that empties and
  /// reloads while the user is on page five asks for five and opens on zero.
  ///
  /// It also focused twice. `initState`'s post-frame callback focuses
  /// `_currentIndex` anyway, and the two requests land inside the
  /// orchestrator's 120 ms settle window, so the first was discarded as stale
  /// and the second paid a delay that a feed's first focus is meant never to
  /// pay. Writing `videoController.currentIndex` from `initState` — which runs
  /// during the host's build — could mark an `Obx` dirty mid-build as well.
  void _applyPendingIndex(int index) {
    final videos = widget.videos;
    final clamped = index
        .clamp(0, videos.isEmpty ? 0 : videos.length - 1)
        .toInt();

    if (!_hasPageController) {
      _currentIndex = clamped;
      return;
    }

    _jumpToPage(clamped);
    unawaited(_focus(clamped));
  }

  @override
  void didUpdateWidget(covariant VideoFeedPager oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.pagerController, widget.pagerController)) {
      oldWidget.pagerController._detach(this);
      widget.pagerController._attach(this);
    }

    _orchestrator.updateVideos(widget.videos);
    _syncIndexWithFeedLength();
  }

  @override
  void deactivate() {
    unawaited(_videoManager.pauseAll(widget.contextKey));
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.pagerController._detach(this);
    _pageController.dispose();
    unawaited(_orchestrator.onDispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isActive = state == AppLifecycleState.resumed;

    if (!_isActive) {
      unawaited(_videoManager.pauseAll(widget.contextKey));
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_focus(_currentIndex));
    });
  }

  // ---------------------------------------------------------------------------
  // Index
  // ---------------------------------------------------------------------------

  /// Keeps the index inside a feed that shrank under us.
  ///
  /// A delete, a refresh or a search clearing can make the list shorter than
  /// the page the user is on. Only the two scoped feeds guarded against it;
  /// the home feed did not, and would build a tile for an index that no
  /// longer existed.
  void _syncIndexWithFeedLength() {
    final length = widget.videos.length;
    if (length <= 0) return;

    final clamped = _currentIndex.clamp(0, length - 1).toInt();
    if (clamped == _currentIndex) return;

    _currentIndex = clamped;
    widget.videoController.currentIndex.value = clamped;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;

      final page = _pageController.page?.round() ?? clamped;
      if (page != clamped) {
        _jumpToPage(clamped);
      }
      unawaited(_focus(clamped));
    });
  }

  void _jumpToPage(int index) {
    if (!_pageController.hasClients) {
      _currentIndex = index;
      return;
    }

    final page = (_pageController.page ?? 0).round();
    if (page == index) {
      _silencedPageIndex = null;
      return;
    }

    _silencedPageIndex = index;
    _pageController.jumpToPage(index);
  }

  Future<void> _focus(int index) async {
    if (!mounted || !_isActive) return;

    final videos = widget.videos;
    if (index < 0 || index >= videos.length) return;

    _hasFocusedOnce = true;

    final previousIndex = _currentIndex;
    _currentIndex = index;
    widget.videoController.currentIndex.value = index;

    final proceed =
        await widget.onBeforeIndexChanged?.call(
          index,
          previousIndex: previousIndex,
        ) ??
        true;
    if (!proceed || !mounted) return;

    // Prefetched from *this* feed's list, not from the controller's own.
    // `prefetchThumbnailsAroundIndex` indexes into `videoList`, so on a
    // search result or a profile feed it was either prefetching the wrong
    // thumbnails or — as the home feed's search branch decided — skipped
    // altogether.
    widget.videoController.prefetchThumbnailsFor(widget.videos, index);

    _orchestrator.updateVideos(widget.videos);
    await _orchestrator.onIndexChanged(index);

    if (!mounted) return;
    await widget.onIndexFocused?.call(index);
  }

  void _onPageChanged(int index) {
    if (index < 0 || index >= widget.videos.length) return;

    if (_silencedPageIndex == index) {
      _silencedPageIndex = null;
      return;
    }

    if (index != _currentIndex) {
      unawaited(HapticFeedback.selectionClick().catchError((_) {}));
    }

    unawaited(_focus(index));
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final videos = widget.videos;
    if (videos.isEmpty) return const SizedBox.shrink();
    if (_currentIndex >= videos.length) return const SizedBox.shrink();

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      physics: const VideoPageScrollPhysics(),
      dragStartBehavior: DragStartBehavior.down,
      allowImplicitScrolling: false,
      itemCount: videos.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final video = videos[index];
        return SmartVideoPlayer(
          key: ValueKey(video.id),
          player: _videoManager.getController(widget.contextKey, video.videoUrl),
          videoController: widget.videoController,
          userController: widget.userController,
          followController: widget.followController,
          contextKey: widget.contextKey,
          videoUrl: video.videoUrl,
          video: video,
          currentIndex: index,
          enableTapToPlay: true,
          autoPlay: true,
          showControls: true,
          showProgressBar: true,
          showDeleteAction: widget.showDeleteAction,
          showProfileAction: widget.showProfileAction,
          onRefreshRequested: widget.onRefreshRequested,
        );
      },
    );
  }
}
