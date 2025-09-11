import 'package:flutter/material.dart';

class LoadingOverlay {
  static final _key = GlobalKey<State<StatefulWidget>>();

  static void show(BuildContext context, {String? message}) {
    if (_key.currentContext != null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        key: _key,
        onWillPop: () async => false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
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
                      style: Theme.of(context).textTheme.titleSmall,
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

  static void hide(BuildContext context) {
    if (_key.currentContext != null) {
      Navigator.of(_key.currentContext!, rootNavigator: true).pop();
    }
  }
}
