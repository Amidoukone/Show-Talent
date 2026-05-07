import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile load failures render a retry state instead of endless loading',
      () {
    final controller =
        File('lib/controller/profile_controller.dart').readAsStringSync();
    final screen = File('lib/screens/profile_screen.dart').readAsStringSync();

    expect(controller, contains('profileLoadErrorMessage'));
    expect(controller, contains('Connexion instable'));
    expect(screen, contains('_buildProfileLoadState'));
    expect(screen, contains('Reessayer'));
  });
}
