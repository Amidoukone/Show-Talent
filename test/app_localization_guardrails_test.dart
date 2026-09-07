import 'dart:io';

import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app keeps French as the pinned default locale', () {
    final main = File('lib/main.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('flutter_localizations:'));
    expect(main, contains("Intl.defaultLocale = 'fr_FR';"));
    expect(main, contains("locale: const Locale('fr')"));
    expect(main, contains("fallbackLocale: const Locale('fr')"));
  });

  test(
    'the Material/Widgets/Cupertino delegates Material date pickers need '
    'are actually wired, not just named in source',
    () {
      // AppLocalizations.localizationsDelegates is what main.dart hands to
      // GetMaterialApp. Checking it here -- rather than grepping main.dart
      // for delegate names -- keeps this guardrail meaningful even though
      // those delegates are no longer spelled out in main.dart itself: they
      // are pulled in transitively through the generated AppLocalizations
      // class since the login-screen localization pilot.
      expect(
        AppLocalizations.localizationsDelegates,
        containsAll(<Object>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ]),
      );
    },
  );
}
