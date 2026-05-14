import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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

class _TiktokVideoPlayerState extends State<TiktokVideoPlayer> {
  // Drag progress used by the progress knob UI.
  double _localDragProgress = 0.0;
  bool _isDragging = false;
  static const double _progressHorizontalPadding = 12.0;

  String? _feedbackOverlay;
  Timer? _feedbackTimer;

  bool _showControlOverlay = false;
  Timer? _overlayTimer;

  Timer? _progressTimer;

  bool _isDisposed = false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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

  void _stopAllTimers() {
    _feedbackTimer?.cancel();
    _overlayTimer?.cancel();
    _progressTimer?.cancel();
  }

  // ---------------------------------------------------------------------------
  // Feedback & overlays
  // ---------------------------------------------------------------------------

  void _showFeedback(String text) {
    if (_isDisposed) return;
    _safeSetState(() => _feedbackOverlay = text);

    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 1), () {
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
    widget.onTogglePlayPause?.call();
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
      _showFeedback(isRight ? "+10s" : "-10s");
      _toggleOverlay();
    } catch (_) {
      // controller potentiellement disposé entre temps
    }
  }

  void _onDragStart(DragStartDetails _) {
    if (_isDisposed) return;
    _safeSetState(() => _isDragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details, VideoPlayerValue val) {
    if (_isDisposed) return;
    if (!_isControllerUsable) return;

    final box = context.findRenderObject() as RenderBox?;
    final totalWidth = box?.size.width ?? MediaQuery.of(context).size.width;
    final trackWidth =
        (totalWidth - (_progressHorizontalPadding * 2)).clamp(0.0, totalWidth);
    final dx = (details.localPosition.dx - _progressHorizontalPadding)
        .clamp(0.0, trackWidth);
    final proportion =
        (trackWidth == 0) ? 0.0 : (dx / trackWidth).clamp(0.0, 1.0);

    _localDragProgress = proportion;

    try {
      widget.controller?.seekTo(val.duration * proportion);
    } catch (_) {}
  }

  void _onDragEnd(DragEndDetails _) {
    if (_isDisposed) return;
    _safeSetState(() => _isDragging = false);
  }

  void _openSpeedMenu() {
    if (!_isControllerUsable) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (_) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [0.75, 1.0, 1.5, 2.0].map((s) {
            return ListTile(
              title: Text("${s}x", style: const TextStyle(color: Colors.white)),
              onTap: () {
                try {
                  widget.controller?.setPlaybackSpeed(s);
                } catch (_) {}
                Navigator.pop(context);
                _showFeedback("${s}x");
              },
            );
          }).toList(),
        );
      },
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
      _stopAllTimers();
      return _buildSafeState(
        showLoader: widget.isLoading || widget.isBuffering,
        errorMessage: widget.errorMessage,
      );
    }
    if (_progressTimer == null || !(_progressTimer?.isActive ?? false)) {
      _startProgressUpdater();
    }

    _ensureProgressUpdaterRunning();

    final value = _safeValue();
    if (value == null) {
      _stopAllTimers();
      return _buildSafeState(
        showLoader: widget.isLoading || widget.isBuffering,
        errorMessage: widget.errorMessage,
      );
    }
    final bool hasError = value.hasError || widget.errorMessage != null;
    final bool hasRenderableFrame =
        _didRenderFrame(value) || widget.hasFirstFrame;
    final bool showLoader = !hasRenderableFrame &&
        (widget.isLoading || value.isBuffering || !value.isInitialized);

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
      VideoPlayerValue value, bool hasError, bool showLoader) {
    if (hasError) {
      return _buildSafeState(
        showLoader: false,
        errorMessage: widget.errorMessage ?? 'Lecture vidéo indisponible.',
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildThumbnail(
          fadeOut: value.isInitialized &&
              (_didRenderFrame(value) || widget.hasFirstFrame),
        ),
        if (value.isInitialized) _buildVideo(),
        if (showLoader) _buildLoadingIndicator(),
      ],
    );
  }

  Widget _buildSafeState({
    required bool showLoader,
    String? errorMessage,
  }) {
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
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.4,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Préparation de la vidéo...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
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

    return CachedNetworkImage(
      imageUrl: thumb,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => _buildThumbnailFallback(),
      errorWidget: (_, __, ___) => _buildThumbnailFallback(),
    );
  }

  Widget _buildThumbnailFallback() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Icon(
        Icons.videocam_off_rounded,
        color: Colors.white54,
        size: 36,
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
        if (_feedbackOverlay != null) _buildFeedbackOverlay(),
        if (_showControlOverlay && widget.showControls)
          _buildFloatingControls(val),
        if (widget.showProgressBar) _buildProgressBar(val),
      ],
    );
  }

  Widget _buildFeedbackOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _feedbackOverlay!,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }

  Widget _buildFloatingControls(VideoPlayerValue val) {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _iconButton(Icons.replay_10, () {
            if (!_isControllerUsable) return;
            try {
              final ctrl = widget.controller!;
              final dur = val.duration;
              final raw = val.position - const Duration(seconds: 10);
              ctrl.seekTo(_clampDuration(raw, Duration.zero, dur));
              _showFeedback("-10s");
            } catch (_) {}
            _toggleOverlay();
          }),
          const SizedBox(width: 16),
          _iconButton(
            val.isPlaying ? Icons.pause : Icons.play_arrow,
            () {
              widget.onTogglePlayPause?.call();
              _toggleOverlay();
            },
          ),
          const SizedBox(width: 16),
          _iconButton(Icons.forward_10, () {
            if (!_isControllerUsable) return;
            try {
              final ctrl = widget.controller!;
              final dur = val.duration;
              final raw = val.position + const Duration(seconds: 10);
              ctrl.seekTo(_clampDuration(raw, Duration.zero, dur));
              _showFeedback("+10s");
            } catch (_) {}
            _toggleOverlay();
          }),
          const SizedBox(width: 16),
          _iconButton(Icons.speed, () {
            _openSpeedMenu();
            _toggleOverlay();
          }),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback? onTap) {
    return CircleAvatar(
      backgroundColor: Colors.black54,
      radius: 22,
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 26),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildProgressBar(VideoPlayerValue val) {
    final durationMs = val.duration.inMilliseconds;
    final posMs = val.position.inMilliseconds.clamp(0, durationMs);
    final percent =
        durationMs == 0 ? 0.0 : (posMs / durationMs).clamp(0.0, 1.0);

    // Si on drag, on utilise la valeur locale (sinon valeur réelle)
    final displayed = _isDragging ? _localDragProgress : percent;
    final clampedDisplayed = displayed.clamp(0.0, 1.0);

    String fmt(Duration d) {
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return "$m:$s";
    }

    final current = Duration(milliseconds: posMs);
    final total = val.duration;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: (d) => _onDragUpdate(d, val),
            onHorizontalDragEnd: _onDragEnd,
            onTapDown: (details) {
              if (!_isControllerUsable) return;
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;

              final width = box.size.width;
              final trackWidth =
                  (width - (_progressHorizontalPadding * 2)).clamp(0.0, width);
              if (trackWidth <= 0) return;

              final tapPos =
                  (details.localPosition.dx - _progressHorizontalPadding)
                      .clamp(0.0, trackWidth);
              final proportion = (tapPos / trackWidth).clamp(0.0, 1.0);

              try {
                widget.controller?.seekTo(val.duration * proportion);
                _showFeedback(fmt(val.duration * proportion));
              } catch (_) {}
              _toggleOverlay();
            },
            child: Container(
              height: 20,
              padding: const EdgeInsets.symmetric(
                  horizontal: _progressHorizontalPadding),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;
                  final knobLeft =
                      (clampedDisplayed * trackWidth).clamp(0.0, trackWidth);

                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white30,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: clampedDisplayed,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Positioned(
                        left: knobLeft - 6,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.greenAccent, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(fmt(current),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
                Text(fmt(total),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorOverlay({String? message}) {
    final resolvedMessage = (message != null && message.trim().isNotEmpty)
        ? message.trim()
        : 'Lecture vidéo indisponible.';

    return Container(
      color: Colors.black.withValues(alpha: 0.35),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_disabled_rounded,
            size: 46,
            color: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            resolvedMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
