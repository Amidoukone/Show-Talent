import 'package:flutter/material.dart';

import '../theme/ad_colors.dart';
import '../theme/ad_tokens.dart';

enum AdSystemNoticeTone { success, info, warning, error }

class AdSystemNoticeData {
  const AdSystemNoticeData({
    required this.title,
    required this.message,
    this.tone = AdSystemNoticeTone.success,
  });

  final String title;
  final String message;
  final AdSystemNoticeTone tone;
}

class AdSystemNotice extends StatelessWidget {
  const AdSystemNotice({
    super.key,
    required this.notice,
    this.onDismiss,
  });

  final AdSystemNoticeData notice;
  final VoidCallback? onDismiss;

  Color get _accent {
    switch (notice.tone) {
      case AdSystemNoticeTone.success:
        return AdColors.success;
      case AdSystemNoticeTone.info:
        return AdColors.info;
      case AdSystemNoticeTone.warning:
        return AdColors.warning;
      case AdSystemNoticeTone.error:
        return AdColors.error;
    }
  }

  IconData get _icon {
    switch (notice.tone) {
      case AdSystemNoticeTone.success:
        return Icons.check_circle_outline_rounded;
      case AdSystemNoticeTone.info:
        return Icons.info_outline_rounded;
      case AdSystemNoticeTone.warning:
        return Icons.priority_high_rounded;
      case AdSystemNoticeTone.error:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AdRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Icon(_icon, color: accent, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdColors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notice.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdColors.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Fermer',
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}
