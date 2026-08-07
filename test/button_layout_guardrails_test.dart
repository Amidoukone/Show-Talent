import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('button themes avoid infinite-width minimum sizes', () {
    final appTheme = File('lib/theme/app_theme.dart').readAsStringSync();
    final adButton = File('lib/widgets/ad_button.dart').readAsStringSync();

    expect(appTheme, isNot(contains('Size.fromHeight(50)')));
    expect(adButton, isNot(contains('Size.fromHeight(')));
    expect(appTheme, contains('minimumSize: const Size(0, 50)'));
    expect(
        adButton,
        contains(
            'minimumSize: Size(0, size == AdButtonSize.regular ? 50 : 44)'));
  });
}
