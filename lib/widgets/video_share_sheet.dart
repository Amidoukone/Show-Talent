import 'package:flutter/material.dart';

import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/utils/video_ui_strings.dart';

/// The row of destinations offered when a viewer taps the share action.
///
/// Deliberately a different sheet from `VideoActionRail`'s "more actions"
/// one: that one lists actions *on* this video (report, delete, add
/// another); this one lists *where* a share goes, each a one-tap shortcut
/// into a specific app, with the platform share sheet still reachable as
/// "Plus" for every target that isn't listed by name (SMS, Mail, Instagram,
/// AirDrop, ...).
///
/// Every callback is responsible for its own result — recording the share,
/// showing a toast, logging a failure — exactly as the lone system-share path
/// already did. This sheet only decides which one runs, then gets out of the
/// way before it does.
Future<void> showVideoShareOptions(
  BuildContext context, {
  required Future<void> Function() onSystemShare,
  required Future<void> Function() onWhatsApp,
  required Future<void> Function() onTelegram,
  required Future<void> Function() onFacebook,
  required Future<void> Function() onCopyLink,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.54),
    builder: (sheetContext) {
      Future<void> run(Future<void> Function() action) {
        Navigator.of(sheetContext).pop();
        return action();
      }

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
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                    Text(
                      VideoUiStrings.shareTitle,
                      style: const TextStyle(
                        color: AdColors.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Horizontally scrollable, never clipped: five destinations
                    // plus labels do not reliably fit the narrowest supported
                    // phone width once the system font-size setting is turned
                    // up, and an `Overflow` here would be a crash on a share
                    // sheet rather than a cosmetic glitch.
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          _ShareDestinationButton(
                            icon: Icons.chat_bubble_rounded,
                            color: const Color(0xFF25D366),
                            label: 'WhatsApp',
                            semanticLabel: VideoUiStrings.shareToWhatsApp,
                            onTap: () => run(onWhatsApp),
                          ),
                          const SizedBox(width: 22),
                          _ShareDestinationButton(
                            icon: Icons.send_rounded,
                            color: const Color(0xFF229ED9),
                            label: 'Telegram',
                            semanticLabel: VideoUiStrings.shareToTelegram,
                            onTap: () => run(onTelegram),
                          ),
                          const SizedBox(width: 22),
                          _ShareDestinationButton(
                            icon: Icons.facebook_rounded,
                            color: const Color(0xFF1877F2),
                            label: 'Facebook',
                            semanticLabel: VideoUiStrings.shareToFacebook,
                            onTap: () => run(onFacebook),
                          ),
                          const SizedBox(width: 22),
                          _ShareDestinationButton(
                            icon: Icons.link_rounded,
                            color: AdColors.onSurfaceMuted,
                            label: VideoUiStrings.copyLink,
                            semanticLabel: VideoUiStrings.copyLink,
                            onTap: () => run(onCopyLink),
                          ),
                          const SizedBox(width: 22),
                          _ShareDestinationButton(
                            icon: Icons.more_horiz_rounded,
                            color: AdColors.onSurfaceMuted,
                            label: VideoUiStrings.moreShareOptions,
                            semanticLabel: VideoUiStrings.moreShareOptions,
                            onTap: () => run(onSystemShare),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ShareDestinationButton extends StatelessWidget {
  const _ShareDestinationButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AdColors.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
