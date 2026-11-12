import 'dart:async';

import 'package:adfoot/l10n/locale_preference.dart';
import 'package:adfoot/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => LocalePreferenceStore.instance.resetForTests());

  testWidgets('renders before startup work has completed', (tester) async {
    final bootstrap = Completer<void>();

    await tester.pumpWidget(
      AppStartupGate(
        bootstrap: () => bootstrap.future,
        readyBuilder: () =>
            const MaterialApp(home: Scaffold(body: Text('application-ready'))),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('application-ready'), findsNothing);

    bootstrap.complete();
    await tester.pump();

    expect(find.text('application-ready'), findsOneWidget);
  });

  testWidgets('keeps the retry path when startup work fails', (tester) async {
    LocalePreferenceStore.instance.resetForTests(current: 'fr');
    var attempts = 0;

    await tester.pumpWidget(
      AppStartupGate(
        bootstrap: () async {
          attempts++;
          if (attempts == 1) {
            throw StateError('offline');
          }
        },
        readyBuilder: () =>
            const MaterialApp(home: Scaffold(body: Text('application-ready'))),
      ),
    );
    await tester.pump();

    expect(find.text('Connexion impossible'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await tester.pump();

    expect(attempts, 2);
    expect(find.text('application-ready'), findsOneWidget);
  });

  // This shell is on the path of every cold start, so copy hardcoded in one
  // language reaches every user in it. It used to: the loading line and the
  // whole retry screen were French string literals, shown unchanged to an
  // account that had picked English in Outils.
  testWidgets('speaks the language the user chose, not French only', (
    tester,
  ) async {
    LocalePreferenceStore.instance.resetForTests(current: 'en');

    await tester.pumpWidget(
      AppStartupGate(
        bootstrap: () async => throw StateError('offline'),
        readyBuilder: () => const SizedBox.shrink(),
      ),
    );
    await tester.pump();

    expect(find.text("Can't start"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Connexion impossible'), findsNothing);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('shows the loading line in the chosen language', (tester) async {
    LocalePreferenceStore.instance.resetForTests(current: 'en');
    final bootstrap = Completer<void>();

    await tester.pumpWidget(
      AppStartupGate(
        bootstrap: () => bootstrap.future,
        readyBuilder: () => const SizedBox.shrink(),
      ),
    );

    expect(find.text('Getting the app ready...'), findsOneWidget);

    bootstrap.complete();
    await tester.pump();
  });
}
