part of 'offre_screen.dart';

/// Replaces the full recruiter identity row on an owner's own offer card --
/// showing your own name/photo on your own post added nothing and pushed
/// the actual offer content down, which is exactly what made a freshly
/// created offer feel "hidden" in the list.
class _OwnerTag extends StatelessWidget {
  const _OwnerTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AdColors.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AdColors.brand.withValues(alpha: 0.32)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_pin_rounded, size: 14, color: AdColors.brand),
          SizedBox(width: 4),
          Text(
            'Votre offre',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AdColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  String _labelFor(String normalized) {
    switch (normalized) {
      case 'ouverte':
        return 'Ouverte';
      case 'fermee':
      case 'fermée':
        return 'Fermée';
      case 'archivee':
      case 'archivée':
        return 'Archivée';
      case 'brouillon':
        return 'Brouillon';
      default:
        return normalized;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color bg;
    Color fg;

    final normalized = status.trim().toLowerCase();

    switch (normalized) {
      case 'ouverte':
        bg = cs.primary.withValues(alpha: 0.14);
        fg = cs.primary;
        break;
      case 'fermee':
      case 'fermée':
        bg = AdColors.error.withValues(alpha: 0.14);
        fg = AdColors.error;
        break;
      case 'archivee':
      case 'archivée':
        bg = AdColors.onSurfaceMuted.withValues(alpha: 0.14);
        fg = AdColors.onSurfaceMuted;
        break;
      default:
        bg = cs.secondary.withValues(alpha: 0.14);
        fg = cs.secondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: const BorderSide(color: AdColors.divider).toBorder(),
      ),
      child: Text(
        _labelFor(normalized),
        style: TextStyle(fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        selectedColor: cs.primary.withValues(alpha: 0.18),
        backgroundColor: AdColors.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: TextStyle(
          color: selected ? cs.primary : cs.onSurface,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
        side: const BorderSide(color: AdColors.divider),
      ),
    );
  }
}

extension _BorderSideX on BorderSide {
  Border toBorder() => Border.fromBorderSide(this);
}
