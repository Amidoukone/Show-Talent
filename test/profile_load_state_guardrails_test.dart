import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'profile load failures render a retry state instead of endless loading',
    () {
      final controller = File(
        'lib/controller/profile_controller.dart',
      ).readAsStringSync();
      final userController = File(
        'lib/controller/user_controller.dart',
      ).readAsStringSync();
      final screen = File('lib/screens/profile_screen.dart').readAsStringSync();
      final mainScreen = File(
        'lib/screens/main_screen.dart',
      ).readAsStringSync();
      final splashScreen = File(
        'lib/screens/splash_screen.dart',
      ).readAsStringSync();

      expect(controller, contains('profileLoadErrorMessage'));
      expect(controller, contains('_profileLoadTimeout'));
      expect(controller, contains('.timeout(_profileLoadTimeout)'));
      expect(controller, contains('Connexion instable'));
      expect(userController, contains('ensureCurrentUserHydrated'));
      expect(userController, contains('_userHydrationTimeout'));
      expect(screen, contains('_buildProfileLoadState'));
      expect(screen, contains('Réessayer'));
      expect(mainScreen, contains('sessionLoadMessage'));
      expect(mainScreen, contains('ensureCurrentUserHydrated'));
      expect(mainScreen, contains('force: true'));

      // A "no profile yet" state must never be a bare spinner with nothing
      // left to complete it. Both screens track whether an attempt has
      // actually settled, and re-arm the load when none has.
      expect(userController, contains('hasAttemptedHydration'));
      expect(controller, contains('hasAttemptedProfileLoad'));
      expect(mainScreen, contains('hasAttemptedHydration'));
      expect(screen, contains('hasAttemptedProfileLoad'));
      expect(splashScreen, contains('_authWatchdogDelay'));
      expect(splashScreen, contains('resolveSessionSafely'));
      expect(splashScreen, contains('_safeOffAllDestination'));
    },
  );
}
