// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/screens/add_video.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/screens/success_toast.dart';
import 'package:adfoot/services/feed_playback_metrics_service.dart';
import 'package:adfoot/services/video_observability_service.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/video_cache_manager.dart' as custom_cache;
import 'package:adfoot/utils/video_share_links.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/tiktok_video_player.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/widgets/video_action_rail.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:adfoot/widgets/video_manager.dart';

part 'smart_video_player_sheets.dart';

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
  bool _isLikeActionLoading = false;
  bool? _queuedLikeTarget;
  bool _isReportActionLoading = false;
  bool _isShareActionLoading = false;
  bool _isDeleteActionLoading = false;
  bool _isAddVideoActionLoading = false;

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

  bool _isRecovering = false;

  /// How many times playback may be rebuilt automatically before the player
  /// stops trying and hands the decision back to the user.
  ///
  /// Every automatic recovery path — the first-frame watchdog (6s), the stall
  /// watchdog (~3s), the buffering watchdog, a runtime value error — ends in
  /// [_purgeAndReloadController], which re-arms the very watchdog that fired
  /// it. Nothing counted the attempts, so a source that can never render a
  /// first frame (a Storage object deleted behind a still-listed document, a
  /// codec the device cannot decode, a captive-portal network) looped
  /// forever: dispose the controller, re-download the whole file, log a
  /// `logPlaybackRetry` callable, wait 6s, repeat — for as long as the video
  /// stayed on screen. The user watched a spinner that could not end while
  /// the phone burned battery, mobile data and Cloud Functions quota.
  ///
  /// Three attempts covers the failures that are genuinely transient (a
  /// stalled stream, a half-written cache file). Past that, the honest answer
  /// is the error overlay, whose "Réessayer" resets this budget — a retry the
  /// user asked for is not a retry loop.
  static const int _maxAutomaticRecoveries = 3;
  int _automaticRecoveryAttempts = 0;
  bool _automaticRecoveryExhausted = false;
  late final FeedPlaybackMetricsLogger _playbackMetricsLogger;
  late final VideoObservabilityService _observability;
  FeedPlaybackSessionTracker? _playbackSession;

  static const double _videoMetadataLeft = 16;
  static const double _videoBottomMinimumOffset = 84;
  static const double _videoBottomSafeGap = 18;
  static const double _videoProgressReservedHeight = 36;
  static const int _captionCollapsedMaxLines = 2;
  static const int _descriptionMaxLines = 1;
  static const List<Shadow> _videoMetadataTextShadow = <Shadow>[
    Shadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x99000000)),
  ];

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _videoManager = VideoManager();
    _playbackMetricsLogger = FeedPlaybackMetricsLogger();
    _observability = VideoObservabilityService.instance;
    _showPlayIcon = ValueNotifier<bool>(true);
    _videoUiSignal = _videoManager.watchVideoUi(
      widget.contextKey,
      widget.videoUrl,
    );

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
      _videoUiSignal = _videoManager.watchVideoUi(
        widget.contextKey,
        widget.videoUrl,
      );
    }

    final videoChanged =
        oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.video.id != widget.video.id;
    final incomingPlayerChanged = !identical(oldWidget.player, widget.player);

    if (videoChanged) {
      _finishPlaybackSession(endReason: 'video_changed');
      _detachListener(_ctrl);
      _player = null;
      _hasFirstFrame = false;
      // A recycled tile must not inherit the previous video's failures.
      _resetAutomaticRecoveryBudget();
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
    final resolvedUrl = _videoManager.getResolvedUrl(
      widget.contextKey,
      widget.videoUrl,
    );
    final canReuseExisting = _videoManager.shouldReuseControllerForRequest(
      originalUrl: widget.videoUrl,
      resolvedUrl: resolvedUrl,
      sources: widget.video.sources,
      isPreload: false,
    );

    CachedVideoPlayerPlus? p;
    if (canReuseExisting) {
      p =
          reuse ??
          _videoManager.getController(widget.contextKey, widget.videoUrl);
    } else {
      AppLogger.debug(
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
          preferDownloadedFile: preferDownloadedFile,
          autoPlay: false,
          activeUrl: widget.videoUrl,
          recoveryReason: recoveryReason,
        );
      } catch (e) {
        AppLogger.debug('[SmartVideoPlayer] init error: $e');
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
    final managedPlayer = _videoManager.getController(
      widget.contextKey,
      widget.videoUrl,
    );
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

    final resolved = _videoManager.getResolvedUrl(
      widget.contextKey,
      widget.videoUrl,
    );
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
        _resetAutomaticRecoveryBudget();
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
    final resolvedUrl =
        _videoManager.getResolvedUrl(widget.contextKey, widget.videoUrl) ??
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
    final resolvedUrl =
        _videoManager.getResolvedUrl(widget.contextKey, widget.videoUrl) ??
        widget.video.resolvedUrl ??
        widget.video.videoUrl;
    final source = _currentPlaybackSource();

    final currentSession = _playbackSession;
    if (currentSession != null) {
      currentSession.updateSource(resolvedUrl: resolvedUrl, source: source);
      return;
    }

    _playbackSession = FeedPlaybackSessionTracker(
      videoId: widget.video.id,
      entryContext: widget.contextKey,
      now: DateTime.now,
      playbackMode: widget.video.playback?.mode,
      hasMultipleMp4Sources:
          widget.video.hasMultipleMp4Sources &&
          _videoManager.adaptiveSourcesEnabled,
      networkTier: _videoManager.currentProfile?.tier.name,
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
      resolvedUrl:
          _videoManager.getResolvedUrl(widget.contextKey, widget.videoUrl) ??
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
        unawaited(_recoverPlayback(reason: 'runtime_value_error'));
      } else {
        _becomePassive();
      }
      return;
    }

    if (!_hasFirstFrame && _didRenderFirstFrame(v)) {
      _hasFirstFrame = true;
      _bufferingStrikes = 0;
      // Playback works: whatever it took to get here is spent, not owed.
      _resetAutomaticRecoveryBudget();
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
        } catch (e, st) {
          AppLogger.debug('[SmartVideoPlayer] play error: $e');
          unawaited(
            _observability.logPlaybackError(
              videoId: widget.video.id,
              videoUrl: widget.videoUrl,
              contextKey: widget.contextKey,
              reason: 'play_error',
              error: e,
              stackTrace: st,
              metadata: _playbackDiagnostics(),
            ),
          );
          if (mounted && !_isDisposed) {
            await _recoverPlayback(reason: 'play_error');
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
            await _recoverPlayback(reason: 'buffering_watchdog');
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
          await _recoverPlayback(reason: 'stall_watchdog');
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
      await _recoverPlayback(reason: 'first_frame_timeout');
    });
  }

  void _stopFirstFrameWatchdog() {
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
  }

  /// Gives playback a clean slate: the source changed, or it finally worked.
  void _resetAutomaticRecoveryBudget() {
    _automaticRecoveryAttempts = 0;
    _automaticRecoveryExhausted = false;
  }

  Future<void> _recoverPlayback({required String reason}) async {
    if (_isDisposed || _isRecovering || _automaticRecoveryExhausted) return;

    if (_automaticRecoveryAttempts >= _maxAutomaticRecoveries) {
      // Stop rebuilding and say so. Leaving the watchdogs armed would restart
      // the loop on the next tick; the overlay's retry is the way back in.
      _automaticRecoveryExhausted = true;
      _stopFirstFrameWatchdog();
      _stopStallWatchdog();
      _finishPlaybackSession(endReason: 'recovery_exhausted');
      unawaited(
        _observability.logPlaybackError(
          videoId: widget.video.id,
          videoUrl: widget.videoUrl,
          contextKey: widget.contextKey,
          reason: 'recovery_exhausted',
          error:
              'Automatic playback recovery gave up after '
              '$_maxAutomaticRecoveries attempts (last reason: $reason).',
          metadata: _playbackDiagnostics(),
        ),
      );
      if (mounted && !_isDisposed) setState(() {});
      return;
    }

    // Escalate. The first three automatic attempts used to be the *same*
    // attempt three times, which is worth exactly one: VideoManager opens a
    // cached file whenever one exists and only consults `preferDownloadedFile`
    // when the cache misses, so every retry re-opened the identical bytes.
    //
    // That is not hypothetical. A first-frame timeout is not an init failure —
    // `initialize()` succeeds on a truncated file, it simply never renders —
    // so VideoManager's own fresh-download fallback, which only triggers when
    // init *throws*, never ran either. Reported from production: a video
    // showed "Lecture interrompue" after an upload, and the manual retry
    // played it instantly. The manual path purges the cached file and streams;
    // the automatic path did neither. The budget was being spent proving the
    // same thing three times.
    //
    // So: attempt one reuses what is there, because a genuinely transient
    // stall needs nothing more and re-fetching a good file is wasteful. Every
    // attempt after that does what the manual retry demonstrably does —
    // discard the cached file and stream.
    final isFirstAttempt = _automaticRecoveryAttempts == 0;
    _automaticRecoveryAttempts++;
    _isRecovering = true;
    try {
      _playbackSession?.recordRecoveryAttempt(reason);
      final resolvedUrl =
          _videoManager.getResolvedUrl(widget.contextKey, widget.videoUrl) ??
          widget.video.resolvedUrl ??
          widget.video.effectiveUrl;

      await _purgeAndReloadController(
        purgeCachedFile: !isFirstAttempt,
        preferDownloadedFile: isFirstAttempt && resolvedUrl.isNotEmpty,
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
      builder: (_, _, _) {
        final ctrl = _ctrl;
        final managedPlayer = _videoManager.getController(
          widget.contextKey,
          widget.videoUrl,
        );
        final managedCtrl = managedPlayer?.controller;
        final shouldBindManagedPlayer =
            managedPlayer != null && !identical(managedPlayer, _player);
        final shouldDetachStaleCtrl =
            ctrl != null &&
            (managedCtrl == null || !identical(ctrl, managedCtrl));
        if (shouldBindManagedPlayer || shouldDetachStaleCtrl) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _isDisposed) return;
            if (!shouldBindManagedPlayer && !identical(_ctrl, ctrl)) return;
            _bindPlayer(managedPlayer);
            if (managedPlayer != null &&
                widget.autoPlay &&
                _isActuallyVisible()) {
              _scheduleMaybePlay();
            }
          });
        }

        final effectiveCtrl = (shouldBindManagedPlayer || shouldDetachStaleCtrl)
            ? managedCtrl
            : ctrl;
        final value = _safeValue(effectiveCtrl);
        final loadState = _videoManager.getLoadState(
          widget.contextKey,
          widget.videoUrl,
        );
        final errorMessage = _automaticRecoveryExhausted
            ? VideoUiStrings.playbackInterruptedRetry
            : (_getErrorMessage(loadState) ??
                  (value?.hasError == true
                      ? VideoUiStrings.playbackInterruptedRetry
                      : null));

        return Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _showPlayIcon,
              builder: (_, showIcon, _) {
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
                  onRetry: () {
                    // The user asked for this one, so it re-opens the
                    // automatic budget rather than spending from it.
                    _resetAutomaticRecoveryBudget();
                    unawaited(
                      _purgeAndReloadController(
                        purgeCachedFile: true,
                        recoveryReason: 'manual_retry',
                      ),
                    );
                  },
                );
              },
            ),
            if (widget.showControls) _buildVideoReadabilityScrim(),
            if (widget.showControls) _buildVideoMetadataOverlay(context),
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
        return VideoUiStrings.loadingTooLong;
      case VideoLoadState.errorSource:
        return VideoUiStrings.playbackError;
      default:
        return null;
    }
  }

  Map<String, dynamic> _playbackDiagnostics() {
    final value = _safeValue(_ctrl);
    final resolvedUrl =
        _videoManager.getResolvedUrl(widget.contextKey, widget.videoUrl) ??
        widget.video.resolvedUrl;
    final loadState = _videoManager.getLoadState(
      widget.contextKey,
      widget.videoUrl,
    );

    return {
      'videoId': widget.video.id,
      'contextKey': widget.contextKey,
      'index': widget.currentIndex,
      'isVisible': _isActuallyVisible(),
      'hasFirstFrame': _hasFirstFrame,
      'loadState': loadState?.name,
      'resolvedUrl': resolvedUrl,
      'positionMs': value?.position.inMilliseconds,
      'durationMs': value?.duration.inMilliseconds,
      'isPlaying': value?.isPlaying,
      'isBuffering': value?.isBuffering,
      'hasError': value?.hasError,
      'errorDescription': value?.errorDescription,
    };
  }

  double _videoOverlayBottomOffset(MediaQueryData media) {
    var bottom =
        media.viewPadding.bottom +
        _videoBottomSafeGap +
        (widget.showProgressBar ? _videoProgressReservedHeight : 0);
    if (bottom < _videoBottomMinimumOffset) {
      bottom = _videoBottomMinimumOffset;
    }
    return bottom;
  }

  double _videoActionSpacing(MediaQueryData media) =>
      media.size.height < 700 ? 16 : 20;

  double _videoSectionSpacing(MediaQueryData media) =>
      media.size.height < 700 ? 20 : 24;

  Widget _buildVideoReadabilityScrim() {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          heightFactor: 0.16,
          widthFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _captionNeedsExpansion({
    required BuildContext context,
    required String text,
    required TextStyle style,
    required double maxWidth,
  }) {
    if (text.trim().isEmpty || maxWidth <= 0) return false;

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: _captionCollapsedMaxLines,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);

    return painter.didExceedMaxLines;
  }

  Widget _buildVideoMetadataOverlay(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomOffset = _videoOverlayBottomOffset(media);
    final description = widget.video.description.trim();
    final rawCaption = widget.video.caption.trim();
    final caption = rawCaption;
    final publisher = widget.userController.usersCache[widget.video.uid];
    final publisherName = (publisher?.nom ?? '').trim();
    final publisherRole = (publisher?.role ?? '').trim();
    final hasPublisher = publisherName.isNotEmpty;
    final hasDescription = description.isNotEmpty;

    final publisherStyle = const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      height: 1.2,
      shadows: _videoMetadataTextShadow,
    );
    final descriptionStyle = const TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.22,
      shadows: _videoMetadataTextShadow,
    );
    final captionStyle = const TextStyle(
      color: Colors.white70,
      fontSize: 13,
      height: 1.28,
      shadows: _videoMetadataTextShadow,
    );
    final linkStyle = const TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      height: 1.2,
      shadows: _videoMetadataTextShadow,
    );

    return Positioned(
      left: _videoMetadataLeft + media.viewPadding.left,
      right: VideoActionRail.reservedWidth + media.viewPadding.right,
      bottom: bottomOffset,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final needsExpansion =
              rawCaption.isNotEmpty &&
              _captionNeedsExpansion(
                context: context,
                text: caption,
                style: captionStyle,
                maxWidth: constraints.maxWidth,
              );

          final captionText = Text(
            caption,
            style: captionStyle,
            maxLines: _captionCollapsedMaxLines,
            overflow: TextOverflow.ellipsis,
          );

          return AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasPublisher || hasDescription)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasPublisher)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            // Deliberately unguarded. This used to bail out
                            // when the signed-in profile had not hydrated
                            // yet, so early in a session tapping a publisher's
                            // name did nothing at all — no navigation, no
                            // feedback, nothing to retry against.
                            unawaited(
                              _openPublisherProfile(
                                widget.userController.user?.uid,
                              ),
                            );
                          },
                          child: Semantics(
                            button: true,
                            label: VideoUiStrings.videoPublisherProfileSemantic,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    publisherName,
                                    style: publisherStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (publisherRole.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.32,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.18,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      publisherRole,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        height: 1.2,
                                        shadows: _videoMetadataTextShadow,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      if (hasDescription)
                        Text(
                          description,
                          style: descriptionStyle,
                          maxLines: _descriptionMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                if ((hasPublisher || hasDescription) && caption.isNotEmpty)
                  const SizedBox(height: 8),
                if (caption.isNotEmpty) captionText,
                if (needsExpansion)
                  Semantics(
                    button: true,
                    label: VideoUiStrings.videoCaptionOpen,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showCaptionSheet(
                        publisherName: publisherName,
                        description: description,
                        caption: caption,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Text(VideoUiStrings.seeMore, style: linkStyle),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCaptionSheet({
    required String publisherName,
    required String description,
    required String caption,
  }) {
    if (!mounted || _isDisposed) return;

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.58),
        builder: (_) => _VideoCaptionSheet(
          publisherName: publisherName,
          description: description,
          caption: caption,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Widget _buildActions(
    BuildContext context,
    VideoController videoController,
    UserController userController,
  ) {
    final currentUser = userController.user;
    if (currentUser == null) return const SizedBox();

    final media = MediaQuery.of(context);
    return VideoActionRail(
      video: widget.video,
      currentUser: currentUser,
      publisher: userController.usersCache[widget.video.uid],
      bottomOffset: _videoOverlayBottomOffset(media),
      safeRightInset: media.viewPadding.right,
      actionSpacing: _videoActionSpacing(media),
      sectionSpacing: _videoSectionSpacing(media),
      showDeleteAction: widget.showDeleteAction,
      showProfileAction: widget.showProfileAction,
      isLikeLoading: false,
      isShareLoading: _isShareActionLoading,
      isReportLoading: _isReportActionLoading,
      isDeleteLoading: _isDeleteActionLoading,
      isAddVideoLoading: _isAddVideoActionLoading,
      isFollowLoading: _isFollowActionLoading,
      onDelete: () async => _confirmDelete(context, videoController),
      onLike: () => _toggleLike(videoController, currentUser.uid),
      onShare: () => _shareVideo(videoController),
      onReport: () async =>
          _confirmReport(context, videoController, currentUser.uid),
      onAddVideo: () => _openAddVideo(videoController),
      onOpenProfile: () => _openPublisherProfile(currentUser.uid),
      onFollowPublisher: () => _followPublisher(currentUser.uid),
    );
  }

  // ---------------------------------------------------------------------------
  // LIKE / DELETE / SHARE / RELOAD / WAKELOCK
  // ---------------------------------------------------------------------------

  /// Opens the publisher's profile.
  ///
  /// [currentUserId] only decides whether the profile opens editable, so an
  /// unknown identity is not a reason to refuse: it falls back to read-only,
  /// which is both the safe default and what a viewer wants anyway.
  Future<void> _openPublisherProfile(String? currentUserId) async {
    final isOwner =
        currentUserId != null &&
        currentUserId.isNotEmpty &&
        widget.video.uid == currentUserId;

    await _videoManager.pauseAll(widget.contextKey);
    await _setWakelock(false);
    await Get.to(
      () => ProfileScreen(uid: widget.video.uid, isReadOnly: !isOwner),
    );
    if (mounted && !_isDisposed) {
      _scheduleMaybePlay();
    }
  }

  Future<void> _followPublisher(String currentUserId) async {
    final currentUser = widget.userController.user;
    final isOwner = widget.video.uid == currentUserId;
    final isFollowing =
        currentUser?.followingsList.contains(widget.video.uid) ?? false;
    if (_isFollowActionLoading || isOwner || isFollowing) return;

    setState(() => _isFollowActionLoading = true);
    final success = await widget.followController.followUser(
      currentUserId,
      widget.video.uid,
    );
    if (!success && mounted && !_isDisposed) {
      showErrorToast(VideoUiStrings.followUnavailable);
    }
    if (mounted && !_isDisposed) {
      setState(() => _isFollowActionLoading = false);
    }
  }

  Future<void> _toggleLike(VideoController controller, String userId) async {
    final targetLiked = !widget.video.likes.contains(userId);
    _queuedLikeTarget = targetLiked;
    _setLocalLikeState(userId, targetLiked);

    if (_isLikeActionLoading) {
      return;
    }

    _isLikeActionLoading = true;
    var confirmedLiked = !targetLiked;
    try {
      while (mounted && !_isDisposed && _queuedLikeTarget != null) {
        final targetForRequest = _queuedLikeTarget!;
        final response = await controller.likeVideo(widget.video.id, userId);
        if (!mounted || _isDisposed) {
          return;
        }

        if (!response.success) {
          _queuedLikeTarget = null;
          _setLocalLikeState(userId, confirmedLiked);
          return;
        }

        confirmedLiked = _resolvedLikeState(response, targetForRequest);
        final latestTarget = _queuedLikeTarget;
        if (latestTarget == null || latestTarget == confirmedLiked) {
          _queuedLikeTarget = null;
          _setLocalLikeState(userId, confirmedLiked);
          return;
        }

        _setLocalLikeState(userId, latestTarget);
      }
    } finally {
      _isLikeActionLoading = false;
    }
  }

  void _setLocalLikeState(String userId, bool liked) {
    widget.video.likes.remove(userId);
    if (liked) {
      widget.video.likes.add(userId);
    }
    if (mounted && !_isDisposed) {
      setState(() {});
    }
  }

  bool _resolvedLikeState(ActionResponse response, bool fallback) {
    final rawLiked = response.data?['liked'];
    return rawLiked is bool ? rawLiked : fallback;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    VideoController controller,
  ) async {
    if (_isDeleteActionLoading) return;

    await _showVideoActionSheet(
      context: context,
      icon: Icons.delete_forever_rounded,
      title: VideoUiStrings.deleteVideoTitle,
      message: VideoUiStrings.deleteVideoSheetMessage,
      badgeLabel: VideoUiStrings.sensitiveActionWarning,
      primaryLabel: VideoUiStrings.deleteVideoPrimaryAction,
      secondaryLabel: VideoUiStrings.deleteVideoSecondaryAction,
      toneColor: AdColors.error,
      primaryForegroundColor: AdColors.white,
      onConfirm: () => _deleteVideo(controller),
    );
  }

  Future<void> _showVideoActionSheet({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String message,
    required String badgeLabel,
    required String primaryLabel,
    required String secondaryLabel,
    required Color toneColor,
    required Color primaryForegroundColor,
    required Future<void> Function() onConfirm,
  }) {
    if (!mounted || _isDisposed) return Future<void>.value();

    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (sheetContext) => _VideoActionConfirmationSheet(
        icon: icon,
        title: title,
        message: message,
        badgeLabel: badgeLabel,
        primaryLabel: primaryLabel,
        secondaryLabel: secondaryLabel,
        toneColor: toneColor,
        primaryForegroundColor: primaryForegroundColor,
        onConfirm: onConfirm,
      ),
    );
  }

  Future<void> _deleteVideo(VideoController controller) async {
    if (_isDeleteActionLoading) return;

    if (mounted && !_isDisposed) {
      setState(() => _isDeleteActionLoading = true);
    }

    try {
      await controller.deleteVideo(widget.video.id);
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isDeleteActionLoading = false);
      }
    }
  }

  Future<void> _confirmReport(
    BuildContext context,
    VideoController controller,
    String userId,
  ) async {
    if (_isReportActionLoading) return;

    await _showVideoActionSheet(
      context: context,
      icon: Icons.flag_rounded,
      title: VideoUiStrings.reportVideoTitle,
      message: VideoUiStrings.reportVideoSheetMessage,
      badgeLabel: VideoUiStrings.moderationReviewLabel,
      primaryLabel: VideoUiStrings.reportVideoPrimaryAction,
      secondaryLabel: VideoUiStrings.reportVideoSecondaryAction,
      toneColor: AdColors.warning,
      primaryForegroundColor: AdColors.brandOn,
      onConfirm: () => _reportVideo(controller, userId),
    );
  }

  Future<void> _reportVideo(VideoController controller, String userId) async {
    if (_isReportActionLoading) return;

    if (mounted && !_isDisposed) {
      setState(() => _isReportActionLoading = true);
    }

    try {
      final response = await controller.signalerVideo(widget.video.id, userId);
      if (response.success) {
        if (!widget.video.reports.contains(userId)) {
          widget.video.reports.add(userId);
        }
        final updatedCount = response.data?['reportCount'] as int?;
        if (updatedCount != null) {
          widget.video.reportCount = updatedCount;
        }
      }
      if (mounted && !_isDisposed) setState(() {});
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isReportActionLoading = false);
      }
    }
  }

  Future<void> _openAddVideo(VideoController controller) async {
    if (_isAddVideoActionLoading) return;

    if (mounted && !_isDisposed) {
      setState(() => _isAddVideoActionLoading = true);
    }

    try {
      await _videoManager.pauseAll(widget.contextKey);
      await _setWakelock(false);
      final result = await Get.to(() => const AddVideo());
      if (result == true) {
        final refreshed = widget.onRefreshRequested != null
            ? await widget.onRefreshRequested!()
            : await controller.refreshVideos();
        if (!refreshed) {
          _scheduleMaybePlay();
        }
      } else {
        _scheduleMaybePlay();
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isAddVideoActionLoading = false);
      }
    }
  }

  Future<void> _shareVideo(VideoController controller) async {
    if (_isShareActionLoading) return;

    final shareUrl = VideoShareLinks.buildVideoUrl(widget.video.id);
    if (shareUrl == null || shareUrl.isEmpty) {
      unawaited(
        _observability.logActionFailure(
          action: 'shareVideo',
          videoId: widget.video.id,
          code: 'missing-share-url',
          message: VideoUiStrings.missingShareUrlLog,
          metadata: {
            'contextKey': widget.contextKey,
            'index': widget.currentIndex,
          },
        ),
      );
      showInfoToast(VideoUiStrings.missingShareUrl);
      return;
    }

    if (mounted && !_isDisposed) {
      setState(() => _isShareActionLoading = true);
    }

    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: _buildShareText(shareUrl),
          title: VideoUiStrings.shareTitle,
          subject: VideoUiStrings.shareSubject,
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
    } catch (error, stackTrace) {
      unawaited(
        _observability.logActionFailure(
          action: 'shareVideo',
          videoId: widget.video.id,
          code: 'client-share-exception',
          message: error.toString(),
          metadata: {
            'contextKey': widget.contextKey,
            'index': widget.currentIndex,
            'stackTrace': stackTrace.toString(),
          },
        ),
      );
      showErrorToast(VideoUiStrings.shareUnavailable);
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isShareActionLoading = false);
      }
    }
  }

  String _buildShareText(String shareUrl) {
    return VideoUiStrings.buildShareText(
      shareUrl: shareUrl,
      caption: widget.video.caption,
    );
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
    bool purgeCachedFile = false,
    bool preferDownloadedFile = false,
    String? recoveryReason,
  }) async {
    if (_isDisposed) return;

    if (recoveryReason != null) {
      unawaited(
        _observability.logPlaybackRetry(
          videoId: widget.video.id,
          videoUrl: widget.videoUrl,
          contextKey: widget.contextKey,
          reason: recoveryReason,
          purgeCachedFile: purgeCachedFile,
          preferDownloadedFile: preferDownloadedFile,
          metadata: _playbackDiagnostics(),
        ),
      );
    }

    // Detach from UI before manager-level dispose to avoid rendering
    // a controller whose native player ID no longer exists.
    _bindPlayer(null);

    final resolvedUrl =
        _videoManager.getResolvedUrl(widget.contextKey, widget.videoUrl) ??
        widget.video.resolvedUrl;
    await _videoManager.disposeUrls(widget.contextKey, [widget.videoUrl]);
    if (!kIsWeb && purgeCachedFile) {
      try {
        final cacheUrl = resolvedUrl ?? widget.videoUrl;
        // removeFile as well as deleting the bytes: deleting only the file
        // leaves the cache repository still holding a CacheObject that points
        // at nothing, so the entry lingers and counts against the store
        // forever. `getFileIfCached` tolerates that — it checks `exists()` —
        // but the phantom never expires on its own.
        await custom_cache.VideoCacheManager.removeCachedFile(cacheUrl);
        final file = await custom_cache.VideoCacheManager.getFileIfCached(
          cacheUrl,
        );
        if (file != null && await file.exists()) {
          await file.delete();
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
