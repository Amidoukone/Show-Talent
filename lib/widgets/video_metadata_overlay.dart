import 'package:flutter/material.dart';

import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/video_action_rail.dart';

/// The geometry the two overlays of a video tile share.
///
/// The metadata column and the action rail have to agree on where the bottom
/// of the tile is, or the caption slides under the progress bar on some
/// devices and floats above it on others. It was agreed by two private
/// methods on the player; now there is one answer.
class VideoOverlayMetrics {
  const VideoOverlayMetrics._();

  static const double metadataLeft = 16;
  static const double bottomMinimumOffset = 84;
  static const double bottomSafeGap = 18;
  static const double progressReservedHeight = 36;

  /// How far above the bottom edge both overlays sit.
  static double bottomOffset(
    MediaQueryData media, {
    required bool showProgressBar,
  }) {
    var bottom =
        media.viewPadding.bottom +
        bottomSafeGap +
        (showProgressBar ? progressReservedHeight : 0);
    if (bottom < bottomMinimumOffset) {
      bottom = bottomMinimumOffset;
    }
    return bottom;
  }

  static double actionSpacing(MediaQueryData media) =>
      media.size.height < 700 ? 16 : 20;

  static double sectionSpacing(MediaQueryData media) =>
      media.size.height < 700 ? 20 : 24;
}

/// Darkens the top of the frame so the chrome above stays readable.
class VideoReadabilityScrim extends StatelessWidget {
  const VideoReadabilityScrim({super.key});

  @override
  Widget build(BuildContext context) {
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
}

/// Who published this video, what they said about it, and its caption.
///
/// Pure presentation, lifted out of `SmartVideoPlayer`: it reads no playback
/// state and holds none, so it does not belong in a widget whose other job is
/// running watchdogs over a native player. It reports taps and lets the
/// player decide what a tap means — the player is the one that has to pause
/// playback before navigating away.
class VideoMetadataOverlay extends StatelessWidget {
  const VideoMetadataOverlay({
    super.key,
    required this.description,
    required this.caption,
    required this.publisherName,
    required this.publisherRole,
    required this.showProgressBar,
    required this.onOpenPublisher,
    required this.onOpenCaption,
  });

  static const int captionCollapsedMaxLines = 2;
  static const int descriptionMaxLines = 1;

  static const List<Shadow> textShadow = <Shadow>[
    Shadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x99000000)),
  ];

  final String description;
  final String caption;
  final String publisherName;
  final String publisherRole;
  final bool showProgressBar;
  final VoidCallback onOpenPublisher;

  /// Called with the text to show, so the player can open the sheet.
  final void Function({
    required String publisherName,
    required String description,
    required String caption,
  })
  onOpenCaption;

  /// True when [text] does not fit in [captionCollapsedMaxLines].
  ///
  /// Measured rather than guessed from a character count: the same caption
  /// wraps differently on a narrow phone and a wide one, and "Voir plus" that
  /// opens a sheet showing exactly what was already on screen is worse than
  /// no link at all.
  static bool captionNeedsExpansion({
    required BuildContext context,
    required String text,
    required TextStyle style,
    required double maxWidth,
  }) {
    if (text.trim().isEmpty || maxWidth <= 0) return false;

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: captionCollapsedMaxLines,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);

    return painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final trimmedDescription = description.trim();
    final trimmedCaption = caption.trim();
    final trimmedPublisher = publisherName.trim();
    final trimmedRole = publisherRole.trim();
    final hasPublisher = trimmedPublisher.isNotEmpty;
    final hasDescription = trimmedDescription.isNotEmpty;

    const publisherStyle = TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      height: 1.2,
      shadows: textShadow,
    );
    const descriptionStyle = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.22,
      shadows: textShadow,
    );
    const captionStyle = TextStyle(
      color: Colors.white70,
      fontSize: 13,
      height: 1.28,
      shadows: textShadow,
    );
    const linkStyle = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      height: 1.2,
      shadows: textShadow,
    );

    return Positioned(
      left: VideoOverlayMetrics.metadataLeft + media.viewPadding.left,
      right: VideoActionRail.reservedWidth + media.viewPadding.right,
      bottom: VideoOverlayMetrics.bottomOffset(
        media,
        showProgressBar: showProgressBar,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final needsExpansion =
              trimmedCaption.isNotEmpty &&
              captionNeedsExpansion(
                context: context,
                text: trimmedCaption,
                style: captionStyle,
                maxWidth: constraints.maxWidth,
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
                          // Deliberately unguarded. This used to bail out when
                          // the signed-in profile had not hydrated yet, so
                          // early in a session tapping a publisher's name did
                          // nothing at all — no navigation, no feedback,
                          // nothing to retry against.
                          onTap: onOpenPublisher,
                          child: Semantics(
                            button: true,
                            label: VideoUiStrings.videoPublisherProfileSemantic,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    trimmedPublisher,
                                    style: publisherStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (trimmedRole.isNotEmpty) ...[
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
                                      trimmedRole,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        height: 1.2,
                                        shadows: textShadow,
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
                          trimmedDescription,
                          style: descriptionStyle,
                          maxLines: descriptionMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                if ((hasPublisher || hasDescription) &&
                    trimmedCaption.isNotEmpty)
                  const SizedBox(height: 8),
                if (trimmedCaption.isNotEmpty)
                  Text(
                    trimmedCaption,
                    style: captionStyle,
                    maxLines: captionCollapsedMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (needsExpansion)
                  Semantics(
                    button: true,
                    label: VideoUiStrings.videoCaptionOpen,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onOpenCaption(
                        publisherName: trimmedPublisher,
                        description: trimmedDescription,
                        caption: trimmedCaption,
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
}
