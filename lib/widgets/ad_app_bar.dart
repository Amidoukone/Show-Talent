import 'package:flutter/material.dart';

import '../theme/ad_colors.dart';
import '../theme/ad_tokens.dart';

class AdAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool centerTitle;
  final Widget? leading;
  final bool showBottomDivider;

  /// A widget under the title — a `TabBar`, in practice.
  ///
  /// Takes precedence over [showBottomDivider]: a tab bar draws its own
  /// separation, and a hairline under it would read as a second one.
  final PreferredSizeWidget? bottom;

  const AdAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.centerTitle = true,
    this.leading,
    this.showBottomDivider = false,
    this.bottom,
  });

  @override
  Size get preferredSize {
    final base = subtitle == null ? 56.0 : 72.0;
    // The divider is deliberately not counted: it never was, and every bar in
    // the app is laid out against these two numbers.
    return Size.fromHeight(base + (bottom?.preferredSize.height ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleWidget = subtitle == null
        ? Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: 0,
            ),
          )
        : Column(
            crossAxisAlignment: centerTitle
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: AdSpacing.xxs),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          );

    return AppBar(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      elevation: 0,
      centerTitle: centerTitle,
      leading: leading,
      titleSpacing: AdSpacing.md,
      title: titleWidget,
      actions: actions,
      bottom:
          bottom ??
          (showBottomDivider
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(
                    height: 1,
                    color: AdColors.divider,
                  ),
                )
              : null),
    );
  }
}
