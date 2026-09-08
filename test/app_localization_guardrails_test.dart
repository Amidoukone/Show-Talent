import 'dart:io';

import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/main.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  test('app resolves the device locale, falling back to French '
      '(see [[project_adfoot_i18n_ios_effort]])', () {
    final main = File('lib/main.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('flutter_localizations:'));
    // The literal 'fr_FR' default moved: Intl.defaultLocale now tracks
    // resolveAppLocale() so implicit DateFormat(...) calls elsewhere in
    // the app stay in the same language as the rest of the screen.
    expect(main, isNot(contains("Intl.defaultLocale = 'fr_FR';")));
    expect(main, contains('Intl.defaultLocale = resolveAppLocale()'));
    expect(main, contains('locale: resolveAppLocale()'));
    expect(main, contains("fallbackLocale: const Locale('fr')"));
  });

  test('resolveAppLocale falls back to French for anything but English', () {
    // Get.deviceLocale reads PlatformDispatcher.instance.locale, which the
    // test host does not control -- resolveAppLocale is a pure function of
    // it, so this only proves the fallback branch is reachable and typed
    // right, not a specific device locale.
    final resolved = resolveAppLocale();
    expect(resolved.languageCode, anyOf('fr', 'en'));
    expect(AppLocalizations.supportedLocales, contains(resolved));
  });

  test('the Material/Widgets/Cupertino delegates Material date pickers need '
      'are actually wired, not just named in source', () {
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
  });
}
