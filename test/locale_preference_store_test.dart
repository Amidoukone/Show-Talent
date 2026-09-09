import 'package:adfoot/l10n/locale_preference.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final store = LocalePreferenceStore.instance;

  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    store.resetForTests(loaded: false);
  });

  tearDown(() {
    store.resetForTests();
    Get.reset();
  });

  test('defaults to system when nothing was ever persisted', () async {
    await store.ensureLoaded();
    expect(store.current, LocalePreferenceStore.system);
  });

  test('ensureLoaded picks up a persisted language choice', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      LocalePreferenceStore.storageKey: 'en',
    });
    store.resetForTests(loaded: false);

    await store.ensureLoaded();

    expect(store.current, 'en');
  });

  test('a corrupt or unsupported persisted value falls back to system', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      LocalePreferenceStore.storageKey: 'not-a-real-language',
    });
    store.resetForTests(loaded: false);

    await store.ensureLoaded();

    expect(store.current, LocalePreferenceStore.system);
  });

  test('set() updates current immediately and persists on disk', () async {
    await store.ensureLoaded();

    await store.set('en');
    expect(store.current, 'en');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalePreferenceStore.storageKey), 'en');
  });

  test('set() with an unsupported value normalizes to system', () async {
    await store.ensureLoaded();

    await store.set('de');

    expect(store.current, LocalePreferenceStore.system);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(LocalePreferenceStore.storageKey),
      LocalePreferenceStore.system,
    );
  });

  test('resolveAppLocale prefers an explicit preference over the device locale', () {
    store.resetForTests(current: 'en');
    expect(resolveAppLocale(), const Locale('en'));

    store.resetForTests(current: 'fr');
    expect(resolveAppLocale(), const Locale('fr'));
  });

  test('resolveAppLocale falls back to the device-locale heuristic for system', () {
    store.resetForTests(current: LocalePreferenceStore.system);
    final resolved = resolveAppLocale();
    expect(resolved.languageCode, anyOf('fr', 'en'));
  });
}
