import 'package:flutter/material.dart';

import '../theme/ad_colors.dart';
import '../theme/ad_tokens.dart';
import 'ad_surface_card.dart';

class AdStatePanel extends StatelessWidget {
  const AdStatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  const AdStatePanel.loading({
    super.key,
    this.title = 'Chargement en cours',
    this.message = 'Veuillez patienter quelques secondes.',
  })  : icon = Icons.hourglass_top_rounded,
        action = null;

  const AdStatePanel.empty({
    super.key,
    this.title = 'Aucun element disponible',
    this.message = 'Aucun contenu nest disponible pour le moment.',
    this.action,
  }) : icon = Icons.inbox_outlined;

  const AdStatePanel.error({
    super.key,
    this.title = 'Impossible de charger les donnees',
    this.message = 'Reessayez dans quelques instants.',
    this.action,
  }) : icon = Icons.error_outline_rounded;

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AdSurfaceCard(
      padding: const EdgeInsets.all(AdSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AdColors.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AdRadius.pill),
            ),
            child: Icon(icon, color: AdColors.brand, size: 24),
          ),
          const SizedBox(height: AdSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AdSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: AdColors.onSurfaceMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AdSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
