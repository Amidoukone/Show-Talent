import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('birth year fact is localized without presenting it as exact age', () async {
    final french = await AppLocalizations.delegate.load(const Locale('fr'));
    final english = await AppLocalizations.delegate.load(const Locale('en'));

    expect(french.talentSearchBirthYear(2006), 'Né en 2006');
    expect(english.talentSearchBirthYear(2006), 'Born 2006');
  });
}
