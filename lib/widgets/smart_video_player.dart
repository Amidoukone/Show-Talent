// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/screens/add_video.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/screens/success_toast.dart';
import 'package:adfoot/services/feed_playback_metrics_service.dart';
import 'package:adfoot/utils/video_cache_manager.dart' as custom_cache;
import 'package:adfoot/widgets/tiktok_video_player.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/widgets/video_manager.dart';

class SmartVideoPlayer extends StatefulWidget {
  final CachedVideoPlayerPlus? player;
  final Video video;
  final VideoController videoController;
  final UserController userController;
  final FollowController followController;
  final String contextKey;
  final String videoUrl;
  final int currentIndex;
  final List<Video> videoList;
  final bool enableTapToPlay;
  final bool autoPlay;
  final bool showControls;
  final bool showProgressBar;
  final bool showDeleteAction;
  final bool showProfileAction;
  final Future<bool> Function()? onRefreshRequested;

  const SmartVideoPlayer({
    super.key,
    required this.player,
    required this.video,
    required this.videoController,
    required this.userController,
    required this.followController,
    required this.contextKey,
    required this.videoUrl,
    required this.currentIndex,
    required this.videoList,
    required this.enableTapToPlay,
    required this.autoPlay,
    required this.showControls,
    this.showProgressBar = false,
    this.showDeleteAction = true,
    this.showProfileAction = true,
    this.onRefreshRequested,
  });

  @override
  State<SmartVideoPlayer> createState() => _SmartVideoPlayerState();
}

class _SmartVideoPlayerState extends State<SmartVideoPlayer>
    with WidgetsBindingObserver {
  late final VideoManager _videoManager;
  late final ValueNotifier<bool> _showPlayIcon;
  late ValueListenable<int> _videoUiSignal;

  CachedVideoPlayerPlus? _player;
  VideoPlayerController? get _ctrl => _player?.controller;

  bool _hasFirstFrame = false;
  int _attachToken = 0;

  late VideoController _vc;
  Worker? _indexWorker;

  AppLifecycleState _appState = AppLifecycleState.resumed;
  bool _isTryingToPlay = false;
  bool _wakelockOn = false;
  bool _isDisposed = false;
  bool _isFollowActionLoading = false;
  bool _isShareActionLoading = false;

  bool get _preferHls =>
      _vc.preferHlsPlayback && widget.video.hasAdaptiveHlsSource;

  Timer? _playDebounceTimer;
  static const Duration _playDebounce = Duration(milliseconds: 120);

  Timer? _stallTimer;
  Timer? _firstFrameTimer;
  Duration _lastKnownPos = Duration.zero;
  int _stallStrikes = 0;
  int _bufferingStrikes = 0;
  static const Duration _stallCheckInterval = Duration(milliseconds: 700);
  static const int _stallMaxStrikesBeforeReload = 4;
  static const int _bufferingMaxStrikesBeforeReload = 8;
  static const Duration _firstFrameTimeout = Duration(seconds: 6);

  bool _forceMp4Fallback = false;
  bool _isRecovering = false;
  late final FeedPlaybackMetricsLogger _playbackMetricsLogger;
  FeedPlaybackSessionTracker? _playbackSession;

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _videoManager = VideoManager();
    _playbackMetricsLogger = FeedPlaybackMetricsLogger();
    _showPlayIcon = ValueNotifier<bool>(true);
    _videoUiSignal =
        _videoManager.watchVideoUi(widget.contextKey, widget.videoUrl);

    _vc = widget.videoController;
    _bindIndexWorker();

    if (widget.player != null) {
      _bindPlayer(widget.player);
    } else if (_vc.currentIndex.value == widget.currentIndex) {
      unawaited(_attachOrInitialize());
    }
  }

  @override
  void dispose() {
    _finishPlaybackSession(endReason: 'dispose');
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    try {
      _indexWorker?.dispose();
    } catch (_) {}

    _videoManager.unwatchVideoUi(widget.contextKey, widget.videoUrl);
    _detachListener(_ctrl);
    _showPlayIcon.dispose();
    _playDebounceTimer?.cancel();
    _stopFirstFrameWatchdog();
    _stopStallWatchdog();
    unawaited(_setWakelock(false));

    super.dispose();
  }

  @override
  void deactivate() {
    _finishPlaybackSession(endReason: 'deactivate');
    _becomePassive();
    unawaited(_setWakelock(false));
    super.deactivate();
  }

  @override
  void didUpdateWidget(covariant SmartVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.videoController, widget.videoController)) {
      _vc = widget.videoController;
      _indexWorker?.dispose();
      _bindIndexWorker();
    }

    if (oldWidget.contextKey != widget.contextKey ||
        oldWidget.videoUrl != widget.videoUrl) {
      _videoManager.unwatchVideoUi(oldWidget.contextKey, oldWidget.videoUrl);
      _videoUiSignal =
          _videoManager.watchVideoUi(widget.contextKey, widget.videoUrl);
    }

    final videoChanged = oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.video.id != widget.video.id;
    final incomingPlayerChanged = !identical(oldWidget.player, widget.player);

    if (videoChanged) {
      _finishPlaybackSession(endReason: 'video_changed');
      _detachListener(_ctrl);
      _player = null;
      _hasFirstFrame = false;
      _forceMp4Fallback = false;
      _stopFirstFrameWatchdog();
      _stopStallWatchdog();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        if (widget.player != null) {
          _bindPlayer(widget.player);
          return;
        }
        if (_vc.currentIndex.value == widget.currentIndex) {
          unawaited(_attachOrInitialize());
        }
      });
      return;
    }

    if (incomingPlayerChanged &&
        widget.player != null &&
        !identical(widget.player, _player)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        _bindPlayer(widget.player);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState = state;
    if (!mounted || _isDisposed) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _becomePassive();
    } else if (state == AppLifecycleState.resumed) {
      if (_isActuallyVisible() &&
          (_vc.currentIndex.value == widget.currentIndex)) {
        _scheduleMaybePlay();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PLAYER ATTACH / INIT
  // ---------------------------------------------------------------------------

  Future<void> _attachOrInitialize({
    CachedVideoPlayerPlus? reuse,
    bool preferDownloadedFile = false,
    String? recoveryReason,
  }) async {
    final localToken = ++_attachToken;
    final useHls = _forceMp4Fallback ? false : _preferHls;
    final resolvedUrl =
        _videoManager.getResolvedUrl(widget.contextKey, widget.videoUrl);
    final canReuseExisting = _videoManager.shouldReuseControllerForRequest(
      originalUrl: widget.videoUrl,
      resolvedUrl: resolvedUrl,
      sources: widget.video.sources,
      requestedHls: useHls,
      isPreload: false,
    );

    CachedVideoPlayerPlus? p;
    if (canReuseExisting) {
      p = reuse ??
          _videoManager.getController(widget.contextKey, widget.videoUrl);
    } else {
      debugPrint(
        '[SmartVideoPlayer] skipping reused controller to refresh active source '
        'for ${widget.video.id} (resolved=${resolvedUrl ?? widget.videoUrl})',
      );
    }

    if (p == null) {
      try {
        p = await _videoManager.initializeController(
          widget.contextKey,
          widget.videoUrl,
          sources: widget.video.sources,
          useHls: useHls,
          forceMp4Fallback: _forceMp4Fallback,
          preferDownloadedFile: preferDownloadedFile,
          autoPlay: false,
          activeUrl: widget.videoUrl,
          recoveryFallbackFromSourceType:
              _forceMp4Fallback && _preferHls ? 'hls' : null,
          recoveryReason: recoveryReason,
        );
      } catch (e) {
        debugPrint('[SmartVideoPlayer] init error: $e');
      }
    }

    if (!mounted || _isDisposed || localToken != _attachToken) return;

    _bindPlayer(p);

    if (widget.autoPlay &&
        (_vc.currentIndex.value == widget.currentIndex) &&
        _isActuallyVisible()) {
      _scheduleMaybePlay();
    }
  }

  void _bindManagedPlayerIfAvailable() {
    final managedPlayer =
        _videoManager.getController(widget.contextKey, widget.videoUrl);
    if (managedPlayer == null || identical(managedPlayer, _player)) {
      return;
    }
    _bindPlayer(managedPlayer);
  }

  void _bindIndexWorker() {
    _indexWorker = ever<int>(_vc.currentIndex, (i) {
      if (!mounted || _isDisposed) return;
      if (i == widget.currentIndex) {
        _bindManagedPlayerIfAvailable();
        _scheduleMaybePlay();
      } else {
        _becomePassive();
      }
    });
  }

  void _bindPlayer(CachedVideoPlayerPlus? p) {
    _detachListener(_ctrl);
    _player = p;
    _hasFirstFrame = false;

    final resolved =
        _videoManager.getResolvedUrl(widget.contextKey, widget.videoUrl);
    if (resolved != null &&
        resolved.isNotEmpty &&
        widget.video.resolvedUrl != resolved) {
      widget.video.resolvedUrl = resolved;
    }

    _updatePlaybackSessionSource();

    final ctrl = _ctrl;
    if (_isControllerValid(ctrl)) {
      final value = ctrl!.value;
      ctrl.addListener(_onTick);
      _showPlayIcon.value = !value.isPlaying;
      if (_didRenderFirstFrame(value)) {
        _hasFirstFrame = true;
        _playbackSession?.markFirstFrameRendered();
        _stopFirstFrameWatchdog();
      } else {
        _startFirstFrameWatchdog();
      }
    } else {
      _showPlayIcon.value = true;
      _stopFirstFrameWatchdog();
    }

    if (mounted && !_isDisposed) setState(() {});
    _updateWakelock();
  }

  bool _isControllerValid(VideoPlayerController? ctrl) {
    try {
      return !_isDisposed && ctrl != null && ctrl.value.isInitialized;
    } catch (_) {
      return false;
    }
  }

  void _detachListener(VideoPlayerController? ctrl) {
    try {
      ctrl?.removeListener(_onTick);
    } catch (_) {}
  }

  VideoPlayerValue? _safeValue(VideoPlayerController? ctrl) {
    try {
      return ctrl?.value;
    } catch (_) {
      return null;
    }
  }

  bool _didRenderFirstFrame(VideoPlayerValue v) {
    final hasPosition = v.position > Duration.zero;
    final hasVideoSize = v.size.width > 0 && v.size.height > 0;
    return hasPosition || (v.isPlaying && hasVideoSize);
  }

  VideoSource? _currentPlaybackSource() {
    final resolvedUrl = _videoManager.getResolvedUrl(
          widget.contextKey,
          widget.videoUrl,
        ) ??
        widget.video.resolvedUrl ??
        widget.video.videoUrl;

    for (final source in widget.video.sources) {
      if (source.url == resolvedUrl) {
        return source;
      }
    }

    final fallbackSource = widget.video.playback?.fallbackSource;
    if (fallbackSource?.url == resolvedUrl) {
      return fallbackSource;
    }

    final sourceAsset = widget.video.playback?.sourceAsset;
    if (sourceAsset?.url == resolvedUrl) {
      return sourceAsset;
    }

    if (resolvedUrl.isEmpty) {
      return null;
    }

    return VideoSource(url: resolvedUrl);
  }

  void _ensurePlaybackSession() {
    final resolvedUrl = _videoManager.getResolvedUrl(
          widget.contextKey,
          widget.videoUrl,
        ) ??
        widget.video.resolvedUrl ??
        widget.video.videoUrl;
    final source = _currentPlaybackSource();

    final currentSession = _playbackSession;
    if (currentSession != null) {
      currentSession.updateSource(
        resolvedUrl: resolvedUrl,
        source: source,
      );
      return;
    }

    _playbackSession = FeedPlaybackSessionTracker(
      videoId: widget.video.id,
      entryContext: widget.contextKey,
      now: DateTime.now,
      playbackMode: widget.video.playback?.mode,
      hasMultipleMp4Sources: widget.video.hasMultipleMp4Sources &&
          _videoManager.adaptiveSourcesEnabled,
      networkTier: _videoManager.currentProfile?.tier.name,
      preferHlsRequested: _preferHls,
      resolvedUrl: resolvedUrl,
      source: source,
    );
    if (_hasFirstFrame) {
      _playbackSession?.markFirstFrameRendered();
    }
  }

  void _updatePlaybackSessionSource() {
    final currentSession = _playbackSession;
    if (currentSession == null) {
      return;
    }
    currentSession.updateSource(
      resolvedUrl: _videoManager.getResolvedUrl(
            widget.contextKey,
            widget.videoUrl,
          ) ??
          widget.video.resolvedUrl ??
          widget.video.videoUrl,
      source: _currentPlaybackSource(),
    );
  }

  void _finishPlaybackSession({required String endReason}) {
    final currentSession = _playbackSession;
    if (currentSession == null) {
      return;
    }

    _playbackSession = null;
    final summary = currentSession.finish(endReason: endReason);
    unawaited(_playbackMetricsLogger.logSession(summary));
  }

  // ---------------------------------------------------------------------------
  // TICK / PLAYBACK
  // ---------------------------------------------------------------------------

  void _onTick() {
    if (_isDisposed) return;

    final c = _ctrl;
    VideoPlayerValue? v;
    try {
      if (!_isControllerValid(c)) return;
      v = c!.value;
    } catch (_) {
      _bindPlayer(null);
      return;
    }
    if (v.hasError) {
      _stopFirstFrameWatchdog();
      _stopStallWatchdog();
      if (mounted && !_isDisposed) setState(() {});
      if (_isActuallyVisible()) {
        unawaited(_recoverPlayback(
          forceMp4: _preferHls,
          reason: 'runtime_value_error',
        ));
      } else {
        _becomePassive();
      }
      return;
    }

    if (!_hasFirstFrame && _didRenderFirstFrame(v)) {
      _hasFirstFrame = true;
      _bufferingStrikes = 0;
      _playbackSession?.markFirstFrameRendered();
      _stopFirstFrameWatchdog();
      if (mounted && !_isDisposed) setState(() {});
    }

    _playbackSession?.recordPlaybackSample(
      position: v.position,
      duration: v.duration,
      isBuffering: v.isBuffering,
    );

    _showPlayIcon.value = !v.isPlaying;

    final shouldBePlaying =
        (_vc.currentIndex.value == widget.currentIndex) && _isActuallyVisible();

    if (!shouldBePlaying && v.isPlaying) {
      try {
        c.pause();
      } catch (_) {}
    }

    _updateWakelock();
    _kickStallWatchdog();
  }

  void _updateWakelock() {
    final ctrl = _ctrl;
    if (!_isControllerValid(ctrl)) {
      unawaited(_setWakelock(false));
      return;
    }
    final value = _safeValue(ctrl);
    if (value == null) {
      unawaited(_setWakelock(false));
      return;
    }

    final shouldKeepAwake =
        value.isPlaying && (_vc.currentIndex.value == widget.currentIndex);

    unawaited(_setWakelock(shouldKeepAwake));
  }

  bool _isActuallyVisible() {
    if (!mounted || _isDisposed) return false;
    if (_appState != AppLifecycleState.resumed) return false;

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    return _vc.currentIndex.value == widget.currentIndex;
  }

  void _scheduleMaybePlay() {
    _playDebounceTimer?.cancel();
    _playDebounceTimer = Timer(_playDebounce, _maybePlay);
  }

  Future<void> _maybePlay() async {
    if (_isTryingToPlay || _isDisposed) return;
    _isTryingToPlay = true;

    try {
      var c = _ctrl;
      if (!_isControllerValid(c)) {
        _bindManagedPlayerIfAvailable();
        c = _ctrl;
      }
      if (!_isControllerValid(c) || !_isActuallyVisible()) return;
      final token = _attachToken;
      final resolvedUrl =
          _videoManager.getResolvedUrl(widget.contextKey, widget.videoUrl) ??
              widget.video.resolvedUrl;
      final shouldReuseCurrent = _videoManager.shouldReuseControllerForRequest(
        originalUrl: widget.videoUrl,
        resolvedUrl: resolvedUrl,
        sources: widget.video.sources,
        requestedHls: _forceMp4Fallback ? false : _preferHls,
        isPreload: false,
      );

      if (!shouldReuseCurrent) {
        await _purgeAndReloadController(
          recoveryReason: 'adaptive_quality_upgrade',
        );
        return;
      }

      await _videoManager.pauseAllExcept(widget.contextKey, widget.videoUrl);
      if (_isDisposed || token != _attachToken || !_isActuallyVisible()) return;
      c = _ctrl;
      if (!_isControllerValid(c)) return;
      final value = _safeValue(c);
      if (value == null) return;

      _ensurePlaybackSession();

      if (!value.isPlaying) {
        try {
          await c!.play();
        } catch (e) {
          debugPrint('[SmartVideoPlayer] play error: $e');
          if (mounted && !_isDisposed) {
            await _recoverPlayback(
              forceMp4: _preferHls,
              reason: 'play_error',
            );
          }
          return;
        }
      }

      _updateWakelock();
      _startFirstFrameWatchdog();
      _kickStallWatchdog(forceRestart: true);
    } finally {
      _isTryingToPlay = false;
    }
  }

  void _becomePassive() {
    _finishPlaybackSession(endReason: 'passive');
    final c = _ctrl;
    final value = _safeValue(c);
    if (_isControllerValid(c) && (value?.isPlaying ?? false)) {
      try {
        c?.pause();
      } catch (_) {}
    }
    unawaited(_setWakelock(false));
    _stopFirstFrameWatchdog();
    _stopStallWatchdog();
  }

  // ---------------------------------------------------------------------------
  // STALL WATCHDOG
  // ---------------------------------------------------------------------------

  void _kickStallWatchdog({bool forceRestart = false}) {
    final c = _ctrl;
    final token = _attachToken;
    if (!_isControllerValid(c)) return;
    final currentValue = _safeValue(c);
    if (currentValue == null || !currentValue.isPlaying) return;
    if (_stallTimer != null && !forceRestart) return;

    _stallTimer?.cancel();
    _lastKnownPos = currentValue.position;
    _stallStrikes = 0;
    _bufferingStrikes = 0;

    _stallTimer = Timer.periodic(_stallCheckInterval, (_) async {
      if (_isDisposed || token != _attachToken) {
        _stopStallWatchdog();
        return;
      }
      final liveCtrl = _ctrl;
      if (liveCtrl == null || liveCtrl != c) {
        _stopStallWatchdog();
        return;
      }

      final v = _safeValue(liveCtrl);
      if (v == null || !v.isInitialized || v.hasError || !v.isPlaying) {
        _stopStallWatchdog();
        return;
      }

      if (v.isBuffering) {
        if (!_hasFirstFrame) {
          _bufferingStrikes++;
          if (_bufferingStrikes >= _bufferingMaxStrikesBeforeReload) {
            _bufferingStrikes = 0;
            await _recoverPlayback(
              forceMp4: _preferHls,
              reason: 'buffering_watchdog',
            );
            return;
          }
        }
        _lastKnownPos = v.position;
        return;
      }
      _bufferingStrikes = 0;

      if (v.position <= _lastKnownPos) {
        _stallStrikes++;
        if (_stallStrikes >= _stallMaxStrikesBeforeReload) {
          _stallStrikes = 0;
          await _recoverPlayback(
            forceMp4: _preferHls,
            reason: 'stall_watchdog',
          );
        }
      } else {
        _stallStrikes = 0;
      }

      _lastKnownPos = v.position;
    });
  }

  void _stopStallWatchdog() {
    _stallTimer?.cancel();
    _stallTimer = null;
    _stallStrikes = 0;
    _bufferingStrikes = 0;
    _lastKnownPos = Duration.zero;
  }

  void _startFirstFrameWatchdog() {
    _stopFirstFrameWatchdog();
    final c = _ctrl;
    final token = _attachToken;
    if (!_isControllerValid(c) || _hasFirstFrame) return;

    _firstFrameTimer = Timer(_firstFrameTimeout, () async {
      if (_isDisposed || _hasFirstFrame || !_isActuallyVisible()) return;
      if (token != _attachToken || c != _ctrl) return;
      await _recoverPlayback(
        forceMp4: _preferHls,
        reason: 'first_frame_timeout',
      );
    });
  }

  void _stopFirstFrameWatchdog() {
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
  }

  Future<void> _recoverPlayback({
    required bool forceMp4,
    required String reason,
  }) async {
    if (_isDisposed || _isRecovering) return;
    _isRecovering = true;
    try {
      _playbackSession?.recordRecoveryAttempt(reason);
      final resolvedUrl = _videoManager.getResolvedUrl(
            widget.contextKey,
            widget.videoUrl,
          ) ??
          widget.video.resolvedUrl ??
          widget.video.effectiveUrl;
      final prefersDownloadedRecovery =
          !resolvedUrl.toLowerCase().contains('.m3u8');

      await _purgeAndReloadController(
        forceMp4: forceMp4,
        preferDownloadedFile: prefersDownloadedRecovery,
        recoveryReason: reason,
      );
    } finally {
      _isRecovering = false;
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final videoController = _vc;
    final userController = widget.userController;

    return ValueListenableBuilder<int>(
      valueListenable: _videoUiSignal,
      builder: (_, __, ___) {
        final ctrl = _ctrl;
        final managedPlayer =
            _videoManager.getController(widget.contextKey, widget.videoUrl);
        final managedCtrl = managedPlayer?.controller;
        final shouldDetachStaleCtrl = ctrl != null &&
            (managedCtrl == null || !identical(ctrl, managedCtrl));
        if (shouldDetachStaleCtrl) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _isDisposed) return;
            if (!identical(_ctrl, ctrl)) return;
            _bindPlayer(managedPlayer);
          });
        }

        final effectiveCtrl = shouldDetachStaleCtrl ? managedCtrl : ctrl;
        final value = _safeValue(effectiveCtrl);
        final loadState =
            _videoManager.getLoadState(widget.contextKey, widget.videoUrl);
        final errorMessage = _getErrorMessage(loadState) ??
            (value?.hasError == true
                ? 'Lecture interrompue. Réessayez.'
                : null);

        return Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _showPlayIcon,
              builder: (_, showIcon, __) {
                return TiktokVideoPlayer(
                  controller: effectiveCtrl,
                  isPlaying: value?.isPlaying ?? false,
                  hidePlayPauseIcon: !showIcon,
                  showControls: widget.showControls,
                  showProgressBar: widget.showProgressBar,
                  isBuffering: value?.isBuffering ?? false,
                  isLoading: loadState == VideoLoadState.loading,
                  errorMessage: errorMessage,
                  thumbnailUrl: widget.video.thumbnailUrl,
                  hasFirstFrame: _hasFirstFrame,
                  onTogglePlayPause: () {
                    if (!widget.enableTapToPlay) return;
                    if (_isControllerValid(effectiveCtrl)) {
                      (effectiveCtrl?.value.isPlaying ?? false)
                          ? _becomePassive()
                          : _scheduleMaybePlay();
                    }
                  },
                  onRetry: () => _purgeAndReloadController(
                    purgeCachedFile: true,
                    recoveryReason: 'manual_retry',
                  ),
                );
              },
            ),
            if (widget.showControls)
              _buildActions(context, videoController, userController),
          ],
        );
      },
    );
  }

  String? _getErrorMessage(VideoLoadState? state) {
    switch (state) {
      case VideoLoadState.errorTimeout:
        return 'Chargement trop long';
      case VideoLoadState.errorSource:
        return 'Erreur de lecture';
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Widget _buildActions(
    BuildContext context,
    VideoController videoController,
    UserController userController,
  ) {
    // Actions disponibles pour l'utilisateur connecte.
    final currentUser = userController.user;
    if (currentUser == null) return const SizedBox();

    final isOwner = widget.video.uid == currentUser.uid;
    final isFollowing = currentUser.followingsList.contains(widget.video.uid);

    final screenHeight = MediaQuery.of(context).size.height;
    double bottomOffset = screenHeight * 0.12;
    if (bottomOffset < 80) bottomOffset = 80;
    final isLiked = widget.video.likes.contains(currentUser.uid);

    return Positioned(
      right: 10,
      bottom: bottomOffset,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showDeleteAction && isOwner)
            _animatedActionButton(
              icon: Icons.delete_forever_rounded,
              color: Colors.redAccent,
              label: 'Supprimer',
              onTap: () => _confirmDelete(context, videoController),
              emphasized: true,
            ),
          if (widget.showDeleteAction && isOwner) const SizedBox(height: 24),
          _animatedActionButton(
            icon: isLiked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: isLiked ? Colors.redAccent : Colors.white,
            label: '${widget.video.likes.length}',
            onTap: () => _toggleLike(videoController, currentUser.uid),
            emphasized: isLiked,
          ),
          const SizedBox(height: 24),
          _animatedActionButton(
            icon: Icons.share_rounded,
            color: _isShareActionLoading ? Colors.white70 : Colors.white,
            label: '${widget.video.shareCount}',
            onTap: _isShareActionLoading
                ? null
                : () => _shareVideo(videoController),
            isLoading: _isShareActionLoading,
          ),
          const SizedBox(height: 24),
          _animatedActionButton(
            icon: Icons.flag_rounded,
            color: Colors.white,
            label: '${widget.video.reportCount}',
            onTap: () async => videoController.signalerVideo(
              widget.video.id,
              currentUser.uid,
            ),
          ),
          const SizedBox(height: 28),
          if (currentUser.role == 'joueur')
            Column(
              children: [
                FloatingActionButton(
                  heroTag: 'addVideo_${widget.video.id}',
                  mini: true,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 3,
                  onPressed: () async {
                    await _videoManager.pauseAll(widget.contextKey);
                    await _setWakelock(false);
                    final result = await Get.to(() => const AddVideo());
                    if (result == true) {
                      final refreshed = widget.onRefreshRequested != null
                          ? await widget.onRefreshRequested!()
                          : await videoController.refreshVideos();
                      if (!refreshed) {
                        _scheduleMaybePlay();
                      }
                    } else {
                      _scheduleMaybePlay();
                    }
                  },
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Vidéo',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          if (widget.showProfileAction) ...[
            const SizedBox(height: 24),
            _buildProfileAction(
              context: context,
              currentUserId: currentUser.uid,
              isOwner: isOwner,
              isFollowing: isFollowing,
              userController: userController,
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LIKE / DELETE / SHARE / RELOAD / WAKELOCK
  // ---------------------------------------------------------------------------

  Widget _animatedActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback? onTap,
    bool emphasized = false,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: isLoading
                ? SizedBox(
                    width: emphasized ? 32 : 30,
                    height: emphasized ? 32 : 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  )
                : Icon(
                    icon,
                    color: color,
                    size: emphasized ? 32 : 30,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAction({
    required BuildContext context,
    required String currentUserId,
    required bool isOwner,
    required bool isFollowing,
    required UserController userController,
  }) {
    final followCtrl = widget.followController;
    final publisher = userController.usersCache[widget.video.uid];
    final photoUrl =
        (publisher?.photoProfil ?? widget.video.profilePhoto).trim();

    Future<void> openProfile() async {
      await _videoManager.pauseAll(widget.contextKey);
      await _setWakelock(false);
      await Get.to(
        () => ProfileScreen(
          uid: widget.video.uid,
          isReadOnly: !isOwner,
        ),
      );
      if (mounted && !_isDisposed) {
        _scheduleMaybePlay();
      }
    }

    Future<void> follow() async {
      if (_isFollowActionLoading || isOwner || isFollowing) return;
      setState(() => _isFollowActionLoading = true);
      final success =
          await followCtrl.followUser(currentUserId, widget.video.uid);
      if (!success && mounted && !_isDisposed) {
        Get.snackbar(
          'Erreur',
          'Impossible de s\'abonner pour le moment',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
      if (mounted && !_isDisposed) {
        setState(() => _isFollowActionLoading = false);
      }
    }

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: openProfile,
              child: CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white,
                backgroundImage:
                    photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isEmpty
                    ? const Icon(Icons.person, color: Colors.black)
                    : null,
              ),
            ),
            if (!isOwner && !isFollowing)
              Positioned(
                bottom: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () async {
                    await follow();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: _isFollowActionLoading
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 16,
                          ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Profil Joueur ',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }

  // (le reste du fichier est IDENTIQUE : like, delete, share, reload, wakelock)
  Future<void> _toggleLike(VideoController controller, String userId) async {
    final wasLiked = widget.video.likes.contains(userId);

    if (wasLiked) {
      widget.video.likes.remove(userId);
    } else {
      widget.video.likes.add(userId);
    }
    if (mounted && !_isDisposed) setState(() {});

    final response = await controller.likeVideo(widget.video.id, userId);
    if (!response.success) {
      if (wasLiked) {
        widget.video.likes.add(userId);
      } else {
        widget.video.likes.remove(userId);
      }
      if (mounted && !_isDisposed) setState(() {});
    }
  }

  void _confirmDelete(BuildContext context, VideoController controller) {
    Get.dialog(
      AlertDialog(
        title: const Text('Supprimer la vidéo'),
        content: const Text('Confirmer la suppression ?'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              Get.back();
              await controller.deleteVideo(widget.video.id);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareVideo(VideoController controller) async {
    if (_isShareActionLoading) return;

    final shareUrl = widget.video.effectiveUrl.trim();
    if (shareUrl.isEmpty) {
      showInfoToast('Lien vidéo indisponible pour le partage.');
      return;
    }

    if (mounted && !_isDisposed) {
      setState(() => _isShareActionLoading = true);
    }

    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: _buildShareText(shareUrl),
          title: 'Partager la vidéo',
          subject: 'Vidéo Adfoot',
          sharePositionOrigin: _sharePositionOrigin(),
        ),
      );

      switch (result.status) {
        case ShareResultStatus.dismissed:
          return;
        case ShareResultStatus.success:
        case ShareResultStatus.unavailable:
          break;
      }

      final response = await controller.partagerVideo(widget.video.id);
      if (response.success) {
        final updatedCount = response.data?['shareCount'] as int?;
        if (updatedCount != null) {
          widget.video.shareCount = updatedCount;
        }
        if (mounted && !_isDisposed) setState(() {});
      }
    } catch (_) {
      showErrorToast('Partage impossible pour le moment.');
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isShareActionLoading = false);
      }
    }
  }

  String _buildShareText(String shareUrl) {
    final caption = widget.video.caption.trim();
    if (caption.isEmpty) {
      return 'Regarde cette vidéo sur Adfoot.\n$shareUrl';
    }

    final shortCaption = caption.length > 120
        ? '${caption.substring(0, 117).trim()}...'
        : caption;
    return 'Regarde cette vidéo sur Adfoot : $shortCaption\n$shareUrl';
  }

  Rect? _sharePositionOrigin() {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // RELOAD
  // ---------------------------------------------------------------------------

  Future<void> _purgeAndReloadController({
    bool forceMp4 = false,
    bool purgeCachedFile = false,
    bool preferDownloadedFile = false,
    String? recoveryReason,
  }) async {
    if (_isDisposed) return;
    if (forceMp4) {
      _forceMp4Fallback = true;
    }

    // Detach from UI before manager-level dispose to avoid rendering
    // a controller whose native player ID no longer exists.
    _bindPlayer(null);

    final resolvedUrl = _videoManager.getResolvedUrl(
          widget.contextKey,
          widget.videoUrl,
        ) ??
        widget.video.resolvedUrl;
    await _videoManager.disposeUrls(widget.contextKey, [widget.videoUrl]);
    if (!kIsWeb && purgeCachedFile) {
      try {
        final cacheUrl = resolvedUrl ?? widget.videoUrl;
        if (cacheUrl.toLowerCase().contains('.m3u8')) {
          await CachedVideoPlayerPlus.removeFileFromCache(Uri.parse(cacheUrl));
          await custom_cache.VideoCacheManager.removeCachedFile(cacheUrl);
        } else {
          final file = await custom_cache.VideoCacheManager.getFileIfCached(
            cacheUrl,
          );
          if (file != null && await file.exists()) {
            await file.delete();
          }
        }
      } catch (_) {}
    }
    _hasFirstFrame = false;
    _stopFirstFrameWatchdog();
    _stopStallWatchdog();
    if (mounted && !_isDisposed) setState(() {});
    unawaited(
      _attachOrInitialize(
        reuse: null,
        preferDownloadedFile: preferDownloadedFile,
        recoveryReason: recoveryReason,
      ),
    );
  }

  Future<void> _setWakelock(bool enable) async {
    if (_wakelockOn == enable) return;
    _wakelockOn = enable;
    try {
      enable ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (_) {}
  }
}
