import 'package:flutter/material.dart';

import '../theme/ad_colors.dart';
import '../theme/ad_tokens.dart';
import 'ad_button.dart';
import 'ad_loading_dialog.dart';

class AdBlockingDialogController {
  AdBlockingDialogController._(this._navigator);

  final NavigatorState _navigator;
  bool _isOpen = true;

  void close<T extends Object?>([T? result]) {
    if (!_isOpen) return;
    _isOpen = false;
    _navigator.pop<T>(result);
  }
}

class AdDialogs {
  AdDialogs._();

  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Confirmer',
    String cancelLabel = 'Annuler',
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actionsAlignment: MainAxisAlignment.end,
        actionsPadding: const EdgeInsets.fromLTRB(
          AdSpacing.md,
          0,
          AdSpacing.md,
          AdSpacing.md,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          AdButton(
            label: confirmLabel,
            expanded: false,
            kind: danger ? AdButtonKind.danger : AdButtonKind.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    return result == true;
  }

  static Future<void> info({
    required BuildContext context,
    required String title,
    required String message,
    String buttonLabel = 'Fermer',
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              buttonLabel,
              style: const TextStyle(
                color: AdColors.brand,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static AdBlockingDialogController showBlocking({
    required BuildContext context,
    required Widget child,
    bool barrierDismissible = false,
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);

    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: barrierDismissible,
      builder: (_) => PopScope(
        canPop: false,
        child: child,
      ),
    );

    return AdBlockingDialogController._(navigator);
  }

  static AdBlockingDialogController showLoading({
    required BuildContext context,
    String title = 'Traitement en cours',
    String message = 'Veuillez patienter quelques secondes.',
  }) {
    return showBlocking(
      context: context,
      child: AdLoadingDialog(
        title: title,
        message: message,
      ),
    );
  }
}
