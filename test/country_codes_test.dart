import 'package:adfoot/utils/country_codes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  test('kCountryNamesFr and the English table share the same 114 codes', () {
    expect(kCountryNamesFr.length, 114);
    expect(countriesByName().length, 114);
  });

  group('countryLabel follows Get.locale', () {
    test('resolves French names when the app locale is French', () {
      Get.locale = const Locale('fr');

      expect(countryLabel('FR'), 'France');
      expect(countryLabel('CI'), 'Côte d’Ivoire');
      expect(countryLabel('DE'), 'Allemagne');
    });

    test('resolves English names when the app locale is English', () {
      Get.locale = const Locale('en');

      expect(countryLabel('FR'), 'France');
      expect(countryLabel('CI'), 'Côte d’Ivoire');
      expect(countryLabel('DE'), 'Germany');
    });

    test('falls back to the raw code for an unknown country', () {
      Get.locale = const Locale('fr');
      expect(countryLabel('ZZ'), 'ZZ');
    });

    test('returns empty for a value that is not a two-letter code', () {
      Get.locale = const Locale('fr');
      expect(countryLabel('France'), '');
      expect(countryLabel(null), '');
    });
  });

  group('countriesByName sorts in the active language', () {
    test('sorts by French name', () {
      Get.locale = const Locale('fr');
      final entries = countriesByName();
      final germany = entries.firstWhere((e) => e.key == 'DE');
      expect(germany.value, 'Allemagne');

      final values = entries.map((e) => e.value).toList();
      final sorted = [...values]..sort();
      expect(values, sorted);
    });

    test('sorts by English name', () {
      Get.locale = const Locale('en');
      final entries = countriesByName();
      final germany = entries.firstWhere((e) => e.key == 'DE');
      expect(germany.value, 'Germany');

      final values = entries.map((e) => e.value).toList();
      final sorted = [...values]..sort();
      expect(values, sorted);
    });
  });

  test('isKnownCountryCode and normalizeCountryCode still behave', () {
    expect(isKnownCountryCode('fr'), isTrue);
    expect(isKnownCountryCode('zz'), isFalse);
    expect(normalizeCountryCode(' fr '), 'FR');
    expect(normalizeCountryCode('France'), isNull);
  });
}
