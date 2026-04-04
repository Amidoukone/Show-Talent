import 'package:flutter/material.dart';

import '../theme/ad_colors.dart';
import '../theme/ad_tokens.dart';

class AdSurfaceCard extends StatelessWidget {
  const AdSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AdSpacing.lg),
    this.margin = EdgeInsets.zero,
    this.borderRadius = AdRadius.lg,
    this.showBorder = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(borderRadius),
        border: showBorder ? Border.all(color: AdColors.divider) : null,
        boxShadow: AdShadows.card(Colors.black),
      ),
      child: child,
    );
  }
}
