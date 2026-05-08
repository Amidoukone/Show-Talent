import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'session routing keeps in-app screens instead of always resetting to main',
      () {
    final source =
        File('lib/controller/user_controller.dart').readAsStringSync();

    expect(source, contains('_shouldNavigateToMain'));
    expect(source, contains('currentRoute == AppRoutes.splash'));
    expect(source, contains('currentRoute == AppRoutes.login'));
    expect(source, contains('currentRoute == AppRoutes.verifyEmail'));
    expect(source, contains('currentRoute == AppRoutes.resetPassword'));
    expect(
      source,
      contains('if (!_shouldNavigateToMain(routeArguments: routeArguments))'),
    );
  });
}
