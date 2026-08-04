import 'package:flutter/material.dart';

import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/utils/video_ui_strings.dart';

class VideoPlaybackControls extends StatelessWidget {
  const VideoPlaybackControls({
    super.key,
    required this.isPlaying,
    required this.onReplay10,
    required this.onTogglePlayPause,
    required this.onForward10,
    required this.onSpeed,
  });

  final bool isPlaying;
  final VoidCallback? onReplay10;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onForward10;
  final VoidCallback? onSpeed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          VideoPlaybackControlButton(
            icon: Icons.replay_10,
            semanticLabel: VideoUiStrings.rewindTenSeconds,
            onPressed: onReplay10,
          ),
          const SizedBox(width: 16),
          VideoPlaybackControlButton(
            icon: isPlaying ? Icons.pause : Icons.play_arrow,
            semanticLabel: isPlaying
                ? VideoUiStrings.pauseVideo
                : VideoUiStrings.playVideo,
            onPressed: onTogglePlayPause,
          ),
          const SizedBox(width: 16),
          VideoPlaybackControlButton(
            icon: Icons.forward_10,
            semanticLabel: VideoUiStrings.forwardTenSeconds,
            onPressed: onForward10,
          ),
          const SizedBox(width: 16),
          VideoPlaybackControlButton(
            icon: Icons.speed,
            semanticLabel: VideoUiStrings.playbackSpeed,
            onPressed: onSpeed,
          ),
        ],
      ),
    );
  }
}

class VideoPlaybackControlButton extends StatelessWidget {
  const VideoPlaybackControlButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  static const double extent = 48;

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Tooltip(
        message: semanticLabel,
        child: SizedBox.square(
          dimension: extent,
          child: Material(
            color: Colors.black.withValues(alpha: enabled ? 0.56 : 0.34),
            shape: CircleBorder(
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Icon(
                icon,
                color: enabled ? Colors.white : Colors.white54,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VideoProgressBar extends StatelessWidget {
  const VideoProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.isDragging,
    required this.dragProgress,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTapSeek,
  });

  static const double horizontalPadding = 12;

  final Duration position;
  final Duration duration;
  final bool isDragging;
  final double dragProgress;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final ValueChanged<double> onTapSeek;

  @override
  Widget build(BuildContext context) {
    final durationMs = duration.inMilliseconds;
    final posMs = position.inMilliseconds.clamp(0, durationMs).toInt();
    final percent =
        durationMs == 0 ? 0.0 : (posMs / durationMs).clamp(0.0, 1.0);
    final displayed = isDragging ? dragProgress : percent;
    final clampedDisplayed = displayed.clamp(0.0, 1.0).toDouble();
    final current = Duration(milliseconds: posMs);

    return Semantics(
      container: true,
      label: VideoUiStrings.progressBarSemantic,
      value: VideoUiStrings.playbackProgressValue(current, duration),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 20,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: horizontalPadding,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;
                  final knobLeft = (clampedDisplayed * trackWidth)
                      .clamp(0.0, trackWidth)
                      .toDouble();

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => onDragStart(),
                    onHorizontalDragUpdate: (details) {
                      onDragUpdate(
                        _proportionFromDx(details.localPosition.dx, trackWidth),
                      );
                    },
                    onHorizontalDragEnd: (_) => onDragEnd(),
                    onTapDown: (details) {
                      onTapSeek(
                        _proportionFromDx(details.localPosition.dx, trackWidth),
                      );
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          height: isDragging ? 5 : 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: clampedDisplayed,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            height: isDragging ? 5 : 3,
                            decoration: BoxDecoration(
                              color: AdColors.brand,
                              borderRadius: BorderRadius.circular(999),
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
                                color: AdColors.brand,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AdColors.brand.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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
                Text(
                  VideoUiStrings.formatPlaybackTime(current),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  VideoUiStrings.formatPlaybackTime(duration),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _proportionFromDx(double dx, double trackWidth) {
    if (trackWidth <= 0) return 0;
    return (dx / trackWidth).clamp(0.0, 1.0).toDouble();
  }
}

class VideoPlaybackSpeedSheet extends StatelessWidget {
  const VideoPlaybackSpeedSheet({
    super.key,
    required this.selectedSpeed,
    required this.onSpeedSelected,
    this.speeds = defaultSpeeds,
  });

  static const List<double> defaultSpeeds = [0.75, 1.0, 1.5, 2.0];

  final double selectedSpeed;
  final List<double> speeds;
  final ValueChanged<double> onSpeedSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AdColors.videoOverlayBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(
                      Icons.speed_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        VideoUiStrings.playbackSpeed,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _SpeedPill(speed: selectedSpeed),
                  ],
                ),
                const SizedBox(height: 14),
                ...speeds.map((speed) {
                  final selected = _isSelected(speed);
                  return _SpeedOptionTile(
                    speed: speed,
                    selected: selected,
                    onTap: () => onSpeedSelected(speed),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isSelected(double speed) {
    return (selectedSpeed - speed).abs() < 0.001;
  }
}

class _SpeedPill extends StatelessWidget {
  const _SpeedPill({required this.speed});

  final double speed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: VideoUiStrings.currentPlaybackSpeed,
      value: VideoUiStrings.formatPlaybackSpeed(speed),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AdColors.brand.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AdColors.brand.withValues(alpha: 0.38),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            VideoUiStrings.formatPlaybackSpeed(speed),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedOptionTile extends StatelessWidget {
  const _SpeedOptionTile({
    required this.speed,
    required this.selected,
    required this.onTap,
  });

  final double speed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = VideoUiStrings.formatPlaybackSpeed(speed);

    return Semantics(
      button: true,
      selected: selected,
      label: VideoUiStrings.selectPlaybackSpeed(speed),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: selected
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              key: ValueKey('selected_speed'),
                              color: AdColors.brand,
                              size: 22,
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('unselected_speed'),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
