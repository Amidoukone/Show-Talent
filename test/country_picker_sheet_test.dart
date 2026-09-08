import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/widgets/country_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  Widget host(Widget child) {
    return GetMaterialApp(
      // Pinned, like lib/main.dart pins the real app to French: the test
      // host's default locale is not guaranteed to be French, and this test
      // asserts literal French strings.
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  testWidgets('lets a user filter countries and returns the picked code', (
    tester,
  ) async {
    String? picked;

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                picked = await showCountryPicker(context);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Rechercher un pays'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzzzzzz');
    await tester.pumpAndSettle();

    expect(find.text('Aucun pays trouvé.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'France');
    await tester.pumpAndSettle();

    final resultTile = find.widgetWithText(ListTile, 'France');
    expect(resultTile, findsOneWidget);
    await tester.tap(resultTile);
    await tester.pumpAndSettle();

    expect(picked, 'FR');
  });

  testWidgets('excludes already-selected countries from the list', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                await showCountryPicker(context, excluded: const ['FR']);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'France');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'France'), findsNothing);
    expect(find.text('Aucun pays trouvé.'), findsOneWidget);
  });
}
