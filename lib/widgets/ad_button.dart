import 'package:flutter/material.dart';

import '../theme/ad_colors.dart';
import '../theme/ad_tokens.dart';

enum AdButtonKind { primary, tonal, danger, outline }

enum AdButtonSize { regular, compact }

class AdButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AdButtonKind kind;
  final AdButtonSize size;
  final bool loading;
  final IconData? leading;
  final bool expanded;

  const AdButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = AdButtonKind.primary,
    this.size = AdButtonSize.regular,
    this.loading = false,
    this.leading,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = _buildButton(context);
    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }

  Widget _buildButton(BuildContext context) {
    final icon = loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _progressColorFor(kind),
            ),
          )
        : (leading != null ? Icon(leading, size: 19) : null);

    if (kind == AdButtonKind.outline) {
      return OutlinedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: icon ?? const SizedBox.shrink(),
        label: Text(label),
        style: _outlinedStyle(context),
      );
    }

    return ElevatedButton.icon(
      onPressed: loading ? null : onPressed,
      icon: icon ?? const SizedBox.shrink(),
      label: Text(label),
      style: _elevatedStyle(context),
    );
  }

  ButtonStyle _elevatedStyle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vertical = size == AdButtonSize.regular ? AdSpacing.sm : AdSpacing.xs;

    final base = ElevatedButton.styleFrom(
      minimumSize: Size(0, size == AdButtonSize.regular ? 50 : 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdRadius.md),
      ),
      padding:
          EdgeInsets.symmetric(vertical: vertical, horizontal: AdSpacing.md),
      textStyle: TextStyle(
        fontSize: size == AdButtonSize.regular ? 16 : 14,
        fontWeight: FontWeight.w700,
      ),
      elevation: 0,
    );

    switch (kind) {
      case AdButtonKind.primary:
        return base.copyWith(
          backgroundColor: const WidgetStatePropertyAll(AdColors.brand),
          foregroundColor: const WidgetStatePropertyAll(AdColors.brandOn),
        );
      case AdButtonKind.tonal:
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
      case AdButtonKind.outline:
        return base.copyWith(
          backgroundColor: WidgetStatePropertyAll(cs.surface),
          foregroundColor: const WidgetStatePropertyAll(AdColors.brand),
        );
    }
  }

  ButtonStyle _outlinedStyle(BuildContext context) {
    final vertical = size == AdButtonSize.regular ? AdSpacing.sm : AdSpacing.xs;
    return OutlinedButton.styleFrom(
      minimumSize: Size(0, size == AdButtonSize.regular ? 50 : 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdRadius.md),
      ),
      side: const BorderSide(color: AdColors.brand, width: 1.2),
      padding:
          EdgeInsets.symmetric(vertical: vertical, horizontal: AdSpacing.md),
      textStyle: TextStyle(
        fontSize: size == AdButtonSize.regular ? 15 : 13,
        fontWeight: FontWeight.w700,
      ),
      foregroundColor: AdColors.brand,
    );
  }

  Color _progressColorFor(AdButtonKind kind) {
    switch (kind) {
      case AdButtonKind.primary:
        return AdColors.brandOn;
      case AdButtonKind.tonal:
      case AdButtonKind.outline:
        return AdColors.brand;
      case AdButtonKind.danger:
        return Colors.white;
    }
  }
}
