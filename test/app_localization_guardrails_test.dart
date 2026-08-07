import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app keeps French localization delegates for Material date pickers', () {
    final main = File('lib/main.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('flutter_localizations:'));
    expect(
        main,
        contains(
            "import 'package:flutter_localizations/flutter_localizations.dart';"));
    expect(main, contains("Intl.defaultLocale = 'fr_FR';"));
    expect(main, contains("locale: const Locale('fr', 'FR')"));
    expect(main, contains("fallbackLocale: const Locale('fr', 'FR')"));
    expect(main, contains('GlobalMaterialLocalizations.delegate'));
    expect(main, contains('GlobalWidgetsLocalizations.delegate'));
    expect(main, contains('GlobalCupertinoLocalizations.delegate'));
  });
}
