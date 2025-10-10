import 'package:flutter/material.dart';

/// Gestionnaire d’affichage d’une superposition de chargement bloquante.

class LoadingOverlay {
  static final _key = GlobalKey<State<StatefulWidget>>();

  /// Affiche une boîte de dialogue de chargement non dismissible.
  static void show(BuildContext context, {String? message}) {
    // Empêche d’afficher plusieurs overlays en même temps
    if (_key.currentContext != null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26, // ✅ léger voile visuel pour la clarté
      builder: (_) => PopScope(
        key: _key,
        canPop: false, // ✅ équivalent à onWillPop => false
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      message ?? 'Chargement…',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ferme la boîte de dialogue de chargement si elle est affichée.
  static void hide(BuildContext context) {
    if (_key.currentContext != null) {
      Navigator.of(_key.currentContext!, rootNavigator: true).pop();
    }
  }
}
