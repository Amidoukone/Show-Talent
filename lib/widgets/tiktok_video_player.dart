import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/video_playback_controls.dart';
import 'package:adfoot/widgets/video_state_overlay.dart';

class TiktokVideoPlayer extends StatefulWidget {
  final VideoPlayerController? controller;
  final bool isPlaying;
  final bool hidePlayPauseIcon;
  final bool showControls;
  final bool showProgressBar;
  final bool isBuffering;
  final bool isLoading;
  final String? errorMessage;
  final String thumbnailUrl;
  final bool hasFirstFrame;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onRetry;

  const TiktokVideoPlayer({
    super.key,
    required this.controller,
    required this.isPlaying,
    required this.hidePlayPauseIcon,
    required this.showControls,
    required this.showProgressBar,
    required this.isBuffering,
    required this.isLoading,
    required this.errorMessage,
    required this.thumbnailUrl,
    required this.hasFirstFrame,
    this.onTogglePlayPause,
    this.onRetry,
  });

  @override
  State<TiktokVideoPlayer> createState() => _TiktokVideoPlayerState();
}

class _VideoGestureFeedback {
  const _VideoGestureFeedback({
    required this.label,
    required this.icon,
    required this.alignment,
  });

  final String label;
  final IconData icon;
  final Alignment alignment;
}

class _TiktokVideoPlayerState extends State<TiktokVideoPlayer> {
  // Drag progress used by the progress knob UI.
  double _localDragProgress = 0.0;
  bool _isDragging = false;
  double _playbackSpeed = 1.0;
  static const double _progressBottomSafeGap = 8.0;

  _VideoGestureFeedback? _feedbackOverlay;
  Timer? _feedbackTimer;

  bool _showControlOverlay = false;
  Timer? _overlayTimer;

  Timer? _progressTimer;
  Timer? _slowLoadingTimer;

  bool _isDisposed = false;
  bool _showSlowLoadingHelp = false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  static const Duration _slowLoadingDelay = Duration(milliseconds: 4500);

  @override
  void initState() {
    super.initState();
    _startProgressUpdater();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _feedbackTimer?.cancel();
    _overlayTimer?.cancel();
    _progressTimer?.cancel();
    _slowLoadingTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Central safeguards: the controller can disappear after VideoManager dispose.
  // ---------------------------------------------------------------------------

  bool get _isControllerUsable {
    final c = widget.controller;
    if (_isDisposed) return false;
    if (c == null) return false;
    try {
      // IMPORTANT: avoid touching the player ID after plugin disposal.
      // Reading value can throw, so keep this guarded.
      final v = c.value;
      return v.isInitialized && !v.hasError;
    } catch (_) {
      return false;
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) setState(fn);
  }

  // Clamp Duration because Duration.clamp does not exist.
  Duration _clampDuration(Duration d, Duration min, Duration max) {
    if (d < min) return min;
    if (d > max) return max;
    return d;
  }

  // ---------------------------------------------------------------------------
  // Timers
  // ---------------------------------------------------------------------------

  void _startProgressUpdater() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_isDisposed) return;
      if (!_isControllerUsable) return;
      if (_isDragging) return;
      final value = _safeValue();
      if (value == null) return;
      if (!value.isPlaying && !value.isBuffering) return;
      _safeSetState(() {});
    });
  }

  // Keeps the progress timer active while the player is usable.
  void _ensureProgressUpdaterRunning() {
    if (_progressTimer == null || !(_progressTimer?.isActive ?? false)) {
      _startProgressUpdater();
    }
  }

  void _stopTransientTimers() {
    _feedbackTimer?.cancel();
    _overlayTimer?.cancel();
    _progressTimer?.cancel();
  }

  void _syncSlowLoadingState({
    required bool showLoader,
    required bool hasError,
  }) {
    if (!showLoader || hasError) {
      _slowLoadingTimer?.cancel();
      _slowLoadingTimer = null;
      _showSlowLoadingHelp = false;
      return;
    }

    if (_showSlowLoadingHelp || _slowLoadingTimer != null) {
      return;
    }

    _slowLoadingTimer = Timer(_slowLoadingDelay, () {
      _slowLoadingTimer = null;
      if (_isDisposed) return;
      _safeSetState(() => _showSlowLoadingHelp = true);
    });
  }

  // ---------------------------------------------------------------------------
  // Feedback & overlays
  // ---------------------------------------------------------------------------

  void _showFeedback(
    String label, {
    required IconData icon,
    Alignment alignment = Alignment.center,
  }) {
    if (_isDisposed) return;
    _safeSetState(
      () => _feedbackOverlay = _VideoGestureFeedback(
        label: label,
        icon: icon,
        alignment: alignment,
      ),
    );

    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 850), () {
      if (_isDisposed) return;
      _safeSetState(() => _feedbackOverlay = null);
    });
  }

  void _toggleOverlay() {
    if (!widget.showControls || _isDisposed) return;

    _safeSetState(() => _showControlOverlay = true);

    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 3), () {
      if (_isDisposed) return;
      _safeSetState(() => _showControlOverlay = false);
    });
  }

  // ---------------------------------------------------------------------------
  // Gestures
  // ---------------------------------------------------------------------------

  void _onTap() {
    if (_isDisposed) return;
    final wasPlaying = _safeValue()?.isPlaying ?? widget.isPlaying;
    widget.onTogglePlayPause?.call();
    _showFeedback(
      wasPlaying ? VideoUiStrings.pause : VideoUiStrings.play,
      icon: wasPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
    );
    _toggleOverlay();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    if (!_isControllerUsable) return;
    final ctrl = widget.controller!;
    final width = MediaQuery.of(context).size.width;

    try {
      final v = ctrl.value;
      final pos = v.position;
      final dur = v.duration;
      if (dur == Duration.zero) return;

      final isRight = details.localPosition.dx > width / 2;
      final raw = isRight
          ? pos + const Duration(seconds: 10)
          : pos - const Duration(seconds: 10);
      final clamped = _clampDuration(raw, Duration.zero, dur);

      ctrl.seekTo(clamped);
      _showFeedback(
        isRight
            ? VideoUiStrings.forwardTenSecondsFeedback
            : VideoUiStrings.rewindTenSecondsFeedback,
        icon: isRight ? Icons.forward_10_rounded : Icons.replay_10_rounded,
        alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
      );
      _toggleOverlay();
    } catch (_) {
      // controller potentiellement disposé entre temps
    }
  }

  void _onProgressDragStart() {
    if (_isDisposed) return;
    _safeSetState(() => _isDragging = true);
  }

  void _onProgressChanged(
    double proportion,
    VideoPlayerValue val, {
    bool showFeedback = false,
  }) {
    if (_isDisposed) return;
    if (!_isControllerUsable) return;
    final clamped = proportion.clamp(0.0, 1.0).toDouble();
    _safeSetState(() => _localDragProgress = clamped);
    final target = val.duration * clamped;

    try {
      widget.controller?.seekTo(target);
      if (showFeedback) {
        _showFeedback(
          VideoUiStrings.formatPlaybackTime(target),
          icon: Icons.drag_indicator_rounded,
        );
      }
    } catch (_) {}
  }

  void _onProgressDragEnd() {
    if (_isDisposed) return;
    _safeSetState(() => _isDragging = false);
  }

  Future<void> _openSpeedMenu() async {
    if (!_isControllerUsable) return;

    final selectedSpeed = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return VideoPlaybackSpeedSheet(
          selectedSpeed: _playbackSpeed,
          onSpeedSelected: (speed) {
            Navigator.of(sheetContext).pop(speed);
          },
        );
      },
    );

    if (!mounted || _isDisposed || selectedSpeed == null) return;
    _applyPlaybackSpeed(selectedSpeed);
  }

  void _applyPlaybackSpeed(double speed) {
    if (!_isControllerUsable) return;

    if (mounted && !_isDisposed) {
      setState(() => _playbackSpeed = speed);
    } else {
      _playbackSpeed = speed;
    }

    final controller = widget.controller;
    if (controller != null) {
      unawaited(controller.setPlaybackSpeed(speed).catchError((_) {}));
    }

    _showFeedback(
      VideoUiStrings.formatPlaybackSpeed(speed),
      icon: Icons.speed_rounded,
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  VideoPlayerValue? _safeValue() {
    try {
      return widget.controller?.value;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isControllerUsable) {
      final hasError =
          widget.errorMessage != null && widget.errorMessage!.trim().isNotEmpty;
      final showLoader = !hasError && (widget.isLoading || widget.isBuffering);
      _syncSlowLoadingState(showLoader: showLoader, hasError: hasError);
      _stopTransientTimers();
      return _buildSafeState(
        showLoader: showLoader,
        errorMessage: widget.errorMessage,
      );
    }
    if (_progressTimer == null || !(_progressTimer?.isActive ?? false)) {
      _startProgressUpdater();
    }

    _ensureProgressUpdaterRunning();

    final value = _safeValue();
    if (value == null) {
      final hasError =
          widget.errorMessage != null && widget.errorMessage!.trim().isNotEmpty;
      final showLoader = !hasError && (widget.isLoading || widget.isBuffering);
      _syncSlowLoadingState(showLoader: showLoader, hasError: hasError);
      _stopTransientTimers();
      return _buildSafeState(
        showLoader: showLoader,
        errorMessage: widget.errorMessage,
      );
    }
    final bool hasError = value.hasError || widget.errorMessage != null;
    final bool hasRenderableFrame =
        _didRenderFrame(value) || widget.hasFirstFrame;
    final bool showLoader =
        !hasRenderableFrame &&
        (widget.isLoading || value.isBuffering || !value.isInitialized);
    _syncSlowLoadingState(showLoader: showLoader, hasError: hasError);

    return GestureDetector(
      onTap: _onTap,
      onDoubleTapDown: _onDoubleTapDown,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildContentLayer(value, hasError, showLoader),
          if (value.isInitialized) _buildOverlayUI(value),
        ],
      ),
    );
  }

  Widget _buildContentLayer(
    VideoPlayerValue value,
    bool hasError,
    bool showLoader,
  ) {
    if (hasError) {
      return _buildSafeState(
        showLoader: false,
        errorMessage: widget.errorMessage ?? VideoUiStrings.playbackUnavailable,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildThumbnail(
          fadeOut:
              value.isInitialized &&
              (_didRenderFrame(value) || widget.hasFirstFrame),
        ),
        if (value.isInitialized) _buildVideo(),
        if (showLoader) _buildLoadingIndicator(),
      ],
    );
  }

  Widget _buildSafeState({required bool showLoader, String? errorMessage}) {
    final hasError = errorMessage != null && errorMessage.trim().isNotEmpty;
    return GestureDetector(
      onTap: hasError ? null : _onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildThumbnailImage(),
          if (hasError)
            _buildErrorOverlay(message: errorMessage)
          else if (showLoader)
            _buildLoadingIndicator(),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    final showRetry = _showSlowLoadingHelp && widget.onRetry != null;
    final message = _showSlowLoadingHelp
        ? VideoStateOverlay.slowLoadingMessage
        : VideoStateOverlay.loadingMessage;

    return VideoStateOverlay.loading(
      message: message,
      showRetry: showRetry,
      onRetry: widget.onRetry,
    );
  }

  bool _didRenderFrame(VideoPlayerValue value) {
    final hasPosition = value.position > Duration.zero;
    final hasVideoSize = value.size.width > 0 && value.size.height > 0;
    return hasPosition || (value.isPlaying && hasVideoSize);
  }

  Widget _buildThumbnail({required bool fadeOut}) {
    return AnimatedOpacity(
      opacity: fadeOut ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: _buildThumbnailImage(),
    );
  }

  Widget _buildThumbnailImage() {
    final thumb = widget.thumbnailUrl.trim();
    if (thumb.isEmpty) {
      return _buildThumbnailFallback();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: thumb,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (_, _) => _buildThumbnailFallback(),
          errorWidget: (_, _, _) => _buildThumbnailFallback(),
        ),
        _buildPosterReadabilityScrim(),
      ],
    );
  }

  Widget _buildPosterReadabilityScrim() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: 0.04),
            Colors.black.withValues(alpha: 0.34),
          ],
          stops: const [0.0, 0.46, 1.0],
        ),
      ),
    );
  }

  Widget _buildThumbnailFallback() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF11161C), Color(0xFF050608)],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.video_library_rounded,
          color: Colors.white38,
          size: 38,
        ),
      ),
    );
  }

  Widget _buildVideo() {
    final ctrl = widget.controller;
    if (ctrl == null) return const SizedBox.shrink();

    VideoPlayerValue val;
    try {
      val = ctrl.value;
    } catch (_) {
      return const SizedBox.shrink();
    }

    final double videoW = val.size.width > 0 ? val.size.width : 9.0;
    final double videoH = val.size.height > 0 ? val.size.height : 16.0;

    return Positioned.fill(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          width: videoW,
          height: videoH,
          child: VideoPlayer(ctrl),
        ),
      ),
    );
  }

  Widget _buildOverlayUI(VideoPlayerValue val) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!widget.hidePlayPauseIcon) _buildCenterPlaybackIndicator(val),
        if (_feedbackOverlay != null) _buildFeedbackOverlay(),
        if (_showControlOverlay && widget.showControls)
          _buildFloatingControls(val),
        if (widget.showProgressBar) _buildProgressBar(val),
      ],
    );
  }

  Widget _buildCenterPlaybackIndicator(VideoPlayerValue val) {
    final isPlaying = val.isPlaying;

    return Semantics(
      button: true,
      label: isPlaying ? VideoUiStrings.pauseVideo : VideoUiStrings.playVideo,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.92, end: 1),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SizedBox.square(
                dimension: 72,
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbackOverlay() {
    final feedback = _feedbackOverlay;
    if (feedback == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: Align(
        alignment: feedback.alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 42),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.88, end: 1),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(feedback.icon, color: Colors.white, size: 26),
                    const SizedBox(width: 8),
                    Text(
                      feedback.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingControls(VideoPlayerValue val) {
    return VideoPlaybackControls(
      isPlaying: val.isPlaying,
      onReplay10: () {
        if (!_isControllerUsable) return;
        try {
          final ctrl = widget.controller!;
          final dur = val.duration;
          final raw = val.position - const Duration(seconds: 10);
          ctrl.seekTo(_clampDuration(raw, Duration.zero, dur));
          _showFeedback(
            VideoUiStrings.rewindTenSecondsFeedback,
            icon: Icons.replay_10_rounded,
            alignment: Alignment.centerLeft,
          );
        } catch (_) {}
        _toggleOverlay();
      },
      onTogglePlayPause: () {
        _showFeedback(
          val.isPlaying ? VideoUiStrings.pause : VideoUiStrings.play,
          icon: val.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        );
        widget.onTogglePlayPause?.call();
        _toggleOverlay();
      },
      onForward10: () {
        if (!_isControllerUsable) return;
        try {
          final ctrl = widget.controller!;
          final dur = val.duration;
          final raw = val.position + const Duration(seconds: 10);
          ctrl.seekTo(_clampDuration(raw, Duration.zero, dur));
          _showFeedback(
            VideoUiStrings.forwardTenSecondsFeedback,
            icon: Icons.forward_10_rounded,
            alignment: Alignment.centerRight,
          );
        } catch (_) {}
        _toggleOverlay();
      },
      onSpeed: () {
        unawaited(_openSpeedMenu());
        _toggleOverlay();
      },
    );
  }

  Widget _buildProgressBar(VideoPlayerValue val) {
    return Positioned(
      bottom: _progressBottomOffset(context),
      left: 0,
      right: 0,
      child: VideoProgressBar(
        position: val.position,
        duration: val.duration,
        isDragging: _isDragging,
        dragProgress: _localDragProgress,
        onDragStart: _onProgressDragStart,
        onDragUpdate: (proportion) => _onProgressChanged(proportion, val),
        onDragEnd: _onProgressDragEnd,
        onTapSeek: (proportion) {
          _onProgressChanged(proportion, val, showFeedback: true);
          _toggleOverlay();
        },
      ),
    );
  }

  double _progressBottomOffset(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return bottomInset > 0 ? bottomInset + _progressBottomSafeGap : 0;
  }

  Widget _buildErrorOverlay({String? message}) {
    return VideoStateOverlay.error(message: message, onRetry: widget.onRetry);
  }
}
