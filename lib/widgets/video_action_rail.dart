import 'dart:async';

import 'package:flutter/material.dart';

import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/utils/video_ui_strings.dart';

class VideoActionRail extends StatelessWidget {
  const VideoActionRail({
    super.key,
    required this.video,
    required this.currentUser,
    required this.publisher,
    required this.bottomOffset,
    required this.safeRightInset,
    required this.actionSpacing,
    required this.sectionSpacing,
    required this.showDeleteAction,
    required this.showProfileAction,
    required this.isLikeLoading,
    required this.isShareLoading,
    required this.isReportLoading,
    required this.isDeleteLoading,
    required this.isAddVideoLoading,
    required this.isFollowLoading,
    required this.onDelete,
    required this.onLike,
    required this.onShare,
    required this.onReport,
    required this.onAddVideo,
    required this.onOpenProfile,
    required this.onFollowPublisher,
  });

  static const double rightInset = 12;
  static const double reservedWidth = 92;
  static const double buttonExtent = 48;
  static const double iconSize = 28;
  static const double labelMaxWidth = 68;

  final Video video;
  final AppUser currentUser;
  final AppUser? publisher;
  final double bottomOffset;
  final double safeRightInset;
  final double actionSpacing;
  final double sectionSpacing;
  final bool showDeleteAction;
  final bool showProfileAction;
  final bool isLikeLoading;
  final bool isShareLoading;
  final bool isReportLoading;
  final bool isDeleteLoading;
  final bool isAddVideoLoading;
  final bool isFollowLoading;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onLike;
  final Future<void> Function()? onShare;
  final Future<void> Function()? onReport;
  final Future<void> Function()? onAddVideo;
  final Future<void> Function()? onOpenProfile;
  final Future<void> Function()? onFollowPublisher;

  @override
  Widget build(BuildContext context) {
    final isOwner = video.uid == currentUser.uid;
    final isFollowing = currentUser.followingsList.contains(video.uid);
    final isLiked = video.likes.contains(currentUser.uid);
    final hasReported = video.reports.contains(currentUser.uid);

    return Positioned(
      right: rightInset + safeRightInset,
      bottom: bottomOffset,
      width: reservedWidth - rightInset,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VideoRailActionButton(
              icon: isLiked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isLiked ? Colors.redAccent : Colors.white,
              label: formatActionCount(video.likes.length),
              onTap: isLikeLoading ? null : () => _run(onLike),
              emphasized: isLiked,
              isLoading: isLikeLoading,
              semanticLabel: isLiked
                  ? VideoUiStrings.unlikeVideo
                  : VideoUiStrings.likeVideo,
              semanticValue: VideoUiStrings.likeCountValue(
                video.likes.length,
              ),
            ),
            SizedBox(height: actionSpacing),
            _VideoRailActionButton(
              icon: Icons.share_rounded,
              color: isShareLoading ? Colors.white70 : Colors.white,
              label: formatActionCount(video.shareCount),
              onTap: isShareLoading ? null : () => _run(onShare),
              isLoading: isShareLoading,
              semanticLabel: VideoUiStrings.shareVideo,
              semanticValue: VideoUiStrings.shareCountValue(video.shareCount),
            ),
            if (showProfileAction) ...[
              SizedBox(height: sectionSpacing),
              _buildProfileAction(
                isOwner: isOwner,
                isFollowing: isFollowing,
              ),
            ],
            SizedBox(height: actionSpacing),
            _buildMoreAction(
              context: context,
              isOwner: isOwner,
              hasReported: hasReported,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileAction({
    required bool isOwner,
    required bool isFollowing,
  }) {
    final photoUrl = (publisher?.photoProfil ?? video.profilePhoto).trim();
    final canFollow = !isOwner && !isFollowing && !isFollowLoading;
    final profileSemanticLabel = isOwner
        ? VideoUiStrings.ownProfile
        : isFollowing
            ? VideoUiStrings.followingProfile
            : VideoUiStrings.openProfile;

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Tooltip(
              message: profileSemanticLabel,
              child: Semantics(
                button: true,
                label: profileSemanticLabel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _run(onOpenProfile),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white,
                    backgroundImage:
                        photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl.isEmpty
                        ? const Icon(Icons.person, color: Colors.black)
                        : null,
                  ),
                ),
              ),
            ),
            if (!isOwner)
              Positioned(
                bottom: -6,
                right: -6,
                child: Tooltip(
                  message: isFollowing
                      ? VideoUiStrings.followingProfile
                      : VideoUiStrings.followProfile,
                  child: Semantics(
                    button: !isFollowing,
                    enabled: canFollow,
                    label: isFollowing
                        ? VideoUiStrings.followingProfile
                        : VideoUiStrings.followProfile,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: canFollow ? () => _run(onFollowPublisher) : null,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color:
                              isFollowing ? AdColors.brand : Colors.redAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: isFollowLoading
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : Icon(
                                isFollowing
                                    ? Icons.check_rounded
                                    : Icons.add_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          VideoUiStrings.profile,
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMoreAction({
    required BuildContext context,
    required bool isOwner,
    required bool hasReported,
  }) {
    return _VideoRailActionButton(
      icon: Icons.more_horiz_rounded,
      color: Colors.white,
      label: VideoUiStrings.moreVideoActions,
      onTap: () => _showMoreActions(
        context: context,
        isOwner: isOwner,
        hasReported: hasReported,
      ),
      semanticLabel: VideoUiStrings.moreVideoActionsSemantic,
    );
  }

  void _showMoreActions({
    required BuildContext context,
    required bool isOwner,
    required bool hasReported,
  }) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.54),
        builder: (sheetContext) {
          return SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AdColors.surfaceCard,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.36),
                        blurRadius: 24,
                        offset: const Offset(0, -10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          VideoUiStrings.moreVideoActionsSemantic,
                          style: TextStyle(
                            color: AdColors.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (currentUser.role == 'joueur')
                          _VideoMoreActionTile(
                            icon: Icons.add_rounded,
                            label: VideoUiStrings.addVideoSemantic,
                            color: AdColors.brand,
                            isLoading: isAddVideoLoading,
                            onTap: isAddVideoLoading
                                ? null
                                : () {
                                    Navigator.of(sheetContext).pop();
                                    _run(onAddVideo);
                                  },
                          ),
                        _VideoMoreActionTile(
                          icon: hasReported
                              ? Icons.outlined_flag_rounded
                              : Icons.flag_rounded,
                          label: hasReported
                              ? VideoUiStrings.reportedVideoSemantic
                              : VideoUiStrings.reportVideoSemantic,
                          color:
                              hasReported ? Colors.amberAccent : Colors.white,
                          isLoading: isReportLoading,
                          onTap: hasReported || isReportLoading
                              ? null
                              : () {
                                  Navigator.of(sheetContext).pop();
                                  _run(onReport);
                                },
                        ),
                        if (showDeleteAction && isOwner)
                          _VideoMoreActionTile(
                            icon: Icons.delete_forever_rounded,
                            label: VideoUiStrings.deleteVideoSemantic,
                            color: Colors.redAccent,
                            isLoading: isDeleteLoading,
                            onTap: isDeleteLoading
                                ? null
                                : () {
                                    Navigator.of(sheetContext).pop();
                                    _run(onDelete);
                                  },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String formatActionCount(int count) {
    if (count < 1000) return '$count';
    if (count < 1000000) {
      final value = count / 1000;
      return value >= 10
          ? '${value.toStringAsFixed(0)}k'
          : '${value.toStringAsFixed(1)}k';
    }

    final value = count / 1000000;
    return value >= 10
        ? '${value.toStringAsFixed(0)}M'
        : '${value.toStringAsFixed(1)}M';
  }

  void _run(Future<void> Function()? action) {
    if (action == null) return;
    unawaited(action());
  }
}

class _VideoRailActionButton extends StatelessWidget {
  const _VideoRailActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.emphasized = false,
    this.isLoading = false,
    this.semanticLabel,
    this.semanticValue,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  final bool emphasized;
  final bool isLoading;
  final String? semanticLabel;
  final String? semanticValue;

  @override
  Widget build(BuildContext context) {
    final effectiveLabel = semanticLabel ?? label;

    return Tooltip(
      message: effectiveLabel,
      child: Semantics(
        button: true,
        enabled: onTap != null && !isLoading,
        label: effectiveLabel,
        value: semanticValue,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: VideoActionRail.buttonExtent,
                height: VideoActionRail.buttonExtent,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      Colors.black.withValues(alpha: emphasized ? 0.24 : 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        Colors.white.withValues(alpha: emphasized ? 0.2 : 0.12),
                    width: 1,
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
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      )
                    : Icon(
                        icon,
                        color: color,
                        size: VideoActionRail.iconSize,
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
                constraints: const BoxConstraints(
                  minWidth: 32,
                  maxWidth: VideoActionRail.labelMaxWidth,
                ),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoMoreActionTile extends StatelessWidget {
  const _VideoMoreActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null && !isLoading,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isLoading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      )
                    : Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: onTap == null
                        ? AdColors.onSurfaceMuted
                        : AdColors.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color:
                    Colors.white.withValues(alpha: onTap == null ? 0.18 : 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
