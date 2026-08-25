import 'package:flutter/material.dart';

import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/ad_button.dart';

/// The last page of the feed, once every available video has been shown.
///
/// This catalogue is bounded — a player may publish ten videos, and the whole
/// collection held fourteen on 2026-08-24 — so the feed reaches its end in a
/// couple of minutes, and it has to say so.
///
/// The two alternatives are both worse. A wall (the scroll simply stops)
/// reads as a broken app. A silent loop back to the top reads as a bug the
/// moment the user recognises a clip, which at this catalogue size takes
/// about thirty seconds. Saying "you are up to date" and offering the actions
/// that actually lead somewhere is the honest version, and it is what a
/// finite feed is for: the recruiter's question is whether they have seen
/// everyone, and this answers it.
class VideoFeedEndCard extends StatelessWidget {
  const VideoFeedEndCard({
    super.key,
    required this.videoCount,
    this.onRefresh,
    this.onSearch,
    this.topInset = 0,
  });

  final int videoCount;

  /// Room to leave above the content, beyond the status bar.
  ///
  /// The host's body runs behind its app bar, so on the home feed the top of
  /// this card sits under a blurred gradient. The widget cannot know that on
  /// its own — a feed without an app bar would want nothing here — so the
  /// host says how much.
  final double topInset;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AdSpacing.lg,
              AdSpacing.xl + topInset,
              AdSpacing.lg,
              AdSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AdColors.brand.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AdColors.brand.withValues(alpha: 0.32),
                    ),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AdColors.brand,
                    size: 32,
                  ),
                ),
                const SizedBox(height: AdSpacing.lg),
                Text(
                  VideoUiStrings.feedEndTitle,
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AdSpacing.sm),
                Text(
                  VideoUiStrings.feedEndMessage(videoCount),
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AdSpacing.xl),
                if (onRefresh != null)
                  AdButton(
                    label: VideoUiStrings.feedEndRefreshAction,
                    leading: Icons.refresh_rounded,
                    onPressed: () => onRefresh!(),
                  ),
                if (onRefresh != null && onSearch != null)
                  const SizedBox(height: AdSpacing.sm),
                if (onSearch != null)
                  AdButton(
                    label: VideoUiStrings.feedEndSearchAction,
                    leading: Icons.search_rounded,
                    kind: AdButtonKind.outline,
                    onPressed: onSearch,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
