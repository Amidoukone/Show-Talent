import 'package:flutter/material.dart';

import '../theme/ad_colors.dart';
import '../theme/ad_tokens.dart';

/// Shared titled-card shell used across the profile view and edit screens.
/// Consolidates three previously-divergent local implementations (different
/// radii, and edit screens reading unset Theme.colorScheme fields that fell
/// back to Flutter's generic Material defaults instead of the app palette).
class AdSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const AdSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(AdRadius.lg),
        border: Border.all(color: AdColors.divider),
      ),
      padding: const EdgeInsets.all(AdSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AdColors.brand),
              const SizedBox(width: AdSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AdColors.onSurfaceMuted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AdSpacing.xs),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: AdSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// Header block for profile edit screens (mirrors the neutral dark-card
/// language of the profile view's own header instead of a jarring solid
/// brand-color block).
class AdFormHeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const AdFormHeaderCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AdSpacing.md),
      decoration: BoxDecoration(
        color: AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(AdRadius.lg),
        border: Border.all(color: AdColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AdColors.brand.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: AdColors.brand),
          ),
          const SizedBox(width: AdSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AdColors.onSurfaceMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
