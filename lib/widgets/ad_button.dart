import 'package:flutter/material.dart';
import '../theme/ad_colors.dart';

enum AdButtonKind { primary, tonal, danger }

class AdButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AdButtonKind kind;
  final bool loading;
  final IconData? leading;
  final bool expanded;

  const AdButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = AdButtonKind.primary,
    this.loading = false,
    this.leading,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AdColors.brandOn,
              ),
            )
          : (leading != null ? Icon(leading, size: 20) : const SizedBox.shrink()),
      label: Text(label),
      style: _styleFor(context),
    );

    if (!expanded) return button;

    return SizedBox(width: double.infinity, child: button);
  }

  ButtonStyle _styleFor(BuildContext context) {
    final base = ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      elevation: 0,
    );

    switch (kind) {
      case AdButtonKind.primary:
        return base.copyWith(
          backgroundColor: const WidgetStatePropertyAll(AdColors.brand),
          foregroundColor: const WidgetStatePropertyAll(AdColors.brandOn),
        );
      case AdButtonKind.tonal:
        // ✅ Remplacement withOpacity(.12) -> withValues(alpha: 0.12) pour éviter la dépréciation
        return base.copyWith(
          backgroundColor:
              WidgetStatePropertyAll(AdColors.brand.withValues(alpha: 0.14)),
          foregroundColor: const WidgetStatePropertyAll(AdColors.brand),
        );
      case AdButtonKind.danger:
        return base.copyWith(
          backgroundColor: const WidgetStatePropertyAll(AdColors.error),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
        );
    }
  }
}
