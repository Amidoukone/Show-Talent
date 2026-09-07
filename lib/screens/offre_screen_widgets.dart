part of 'offre_screen.dart';

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  String _labelFor(AppLocalizations l10n, String normalized) {
    switch (normalized) {
      case 'ouverte':
        return l10n.offreStatusOpenLabel;
      case 'fermee':
      case 'fermée':
        return l10n.offreStatusClosedLabel;
      case 'archivee':
      case 'archivée':
        return l10n.offreStatusArchivedLabel;
      case 'brouillon':
        return l10n.offreStatusDraftLabel;
      default:
        return normalized;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
        _labelFor(l10n, normalized),
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
