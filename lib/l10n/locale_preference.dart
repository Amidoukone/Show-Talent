import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show Locale;
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_logger.dart';

/// The user's manually chosen app language, if any.
///
/// Local by design, same reasoning as `WatchedVideoStore`: this is a
/// per-device UI preference, not account data, so it needs no server round
/// trip and nothing here leaves the phone.
///
/// `system` (the default) keeps the app's original behavior of following the
/// device's locale (see [resolveAppLocale]). `fr`/`en` pin the app to that
/// language regardless of what the device is set to, chosen from Parametres
/// > Outils.
class LocalePreferenceStore {
  LocalePreferenceStore._();

  static final LocalePreferenceStore instance = LocalePreferenceStore._();

  static const String storageKey = 'app.locale_preference.v1';
  static const String system = 'system';
  static const Set<String> supportedLanguageCodes = <String>{'fr', 'en'};

  String _current = system;
  Future<void>? _loading;
  bool _loaded = false;

  Future<SharedPreferences> Function() _preferences =
      SharedPreferences.getInstance;

  bool get isLoaded => _loaded;

  /// The active preference: `system`, `fr`, or `en`.
  ///
  /// Safe to read synchronously anywhere once [ensureLoaded] has settled --
  /// `AppBootstrap.initialize()` awaits it before `runApp()`, so by the time
  /// any screen builds, this already reflects what was persisted last
  /// session rather than the default.
  String get current => _current;

  /// Reads the store once. Safe to call from anywhere, any number of times.
  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await _preferences();
      final raw = prefs.getString(storageKey);
      if (raw != null && supportedLanguageCodes.contains(raw)) {
        _current = raw;
      }
    } catch (error) {
      // A corrupt or unreadable preference must never keep the app from
      // starting: the worst case is falling back to the device locale,
      // which is what every build did before this preference existed.
      AppLogger.debug(
        '[LocalePreferenceStore] load failed, using system: $error',
      );
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  /// Persists [value] (`system`, `fr` or `en`; anything else is treated as
  /// `system`).
  ///
  /// In-memory first, so [current] reflects the choice immediately even if
  /// the disk write is still in flight -- same reasoning as
  /// `WatchedVideoStore.markWatched`.
  Future<void> set(String value) async {
    final normalized = value == system || supportedLanguageCodes.contains(value)
        ? value
        : system;
    _current = normalized;
    _loaded = true;

    try {
      final prefs = await _preferences();
      await prefs.setString(storageKey, normalized);
    } catch (error) {
      AppLogger.debug(
        '[LocalePreferenceStore] persist failed for $normalized: $error',
      );
    }
  }

  @visibleForTesting
  void resetForTests({
    String? current,
    Future<SharedPreferences> Function()? preferences,
    bool loaded = true,
  }) {
    _current = current ?? system;
    _preferences = preferences ?? SharedPreferences.getInstance;
    _loading = null;
    _loaded = loaded;
  }
}

/// The app's active locale.
///
/// Only two locales ship copy ([AppLocalizations.supportedLocales]).
/// [LocalePreferenceStore.current] takes priority when it is `fr`/`en` (a
/// manual choice from Outils); otherwise this falls back to the original
/// device-locale heuristic -- an English device gets English, anything else
/// falls back to French, not a device-locale exact match.
///
/// Used both for [AdfootApp]'s `GetMaterialApp.locale` (drives
/// `AppLocalizations` and, via `Get.locale`, the `VideoUiStrings` `.tr`
/// catalog and `country_codes.dart`) and for `Intl.defaultLocale` in
/// `main()` -- keeping both in sync is what stops implicit `DateFormat(...)`
/// calls elsewhere in the app (ones with no explicit locale argument) from
/// rendering month/day names in the wrong language.
Locale resolveAppLocale() {
  final preference = LocalePreferenceStore.instance.current;
  if (preference == 'en') {
    return const Locale('en');
  }
  if (preference == 'fr') {
    return const Locale('fr');
  }

  return Get.deviceLocale?.languageCode == 'en'
      ? const Locale('en')
      : const Locale('fr');
}

/// Applies a manually chosen language (`system`, `fr` or `en`), persists it,
/// and rebuilds the running app in the new language immediately -- no
/// restart needed.
///
/// Must go through here rather than a bare `Get.updateLocale(...)`: the
/// `get` package's `GetMaterialApp` does, on every rebuild, `if (locale !=
/// null) Get.locale = locale;` using `AdfootApp`'s own `locale:
/// resolveAppLocale()` (see `get_material_app.dart` in the installed `get`
/// package). `Get.updateLocale` triggers exactly that rebuild -- so unless
/// [resolveAppLocale] already reflects the new preference *before* the
/// rebuild runs, that line would immediately overwrite `Get.locale` back to
/// the device-derived value, undoing the switch on the very rebuild meant to
/// apply it. Persisting to [LocalePreferenceStore] first is what closes that
/// loop correctly.
Future<void> applyLocalePreference(String value) async {
  await LocalePreferenceStore.instance.set(value);

  final locale = resolveAppLocale();
  Intl.defaultLocale = locale.languageCode == 'en' ? 'en_US' : 'fr_FR';
  await Get.updateLocale(locale);
}
