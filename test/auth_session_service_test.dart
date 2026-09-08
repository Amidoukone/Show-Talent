import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/l10n/video_ui_translations.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  // loginMessage resolves through GetX's `.tr`, which needs
  // Get.locale/Get.translations populated -- set directly (no widget to
  // pump in a pure test) so the assertions below check real French text,
  // not `.tr` silently falling back to the bare key.
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(VideoUiTranslations().keys);
    Get.locale = const Locale('fr');
    Get.fallbackLocale = const Locale('fr');
  });
  tearDown(() {
    Get.clearTranslations();
    Get.reset();
  });

  test('auth session destinations map to the shared route table', () {
    expect(AuthSessionDestination.login.routeName, AppRoutes.login);
    expect(AuthSessionDestination.verifyEmail.routeName, AppRoutes.verifyEmail);
    expect(AuthSessionDestination.main.routeName, AppRoutes.main);
  });

  test('login failure messages stay explicit for product support', () {
    expect(
      UserAccessIssue.missingProfile.loginMessage,
      contains('Compte incomplet'),
    );
    expect(
      UserAccessIssue.adminPortalOnly.loginMessage,
      contains('administration Adfoot'),
    );
    expect(UserAccessIssue.disabledAccount.loginMessage, contains('désactivé'));
  });

  test('transient auth errors are not treated as disabled accounts', () {
    final networkAbort = FirebaseAuthException(
      code: 'network-request-failed',
      message:
          'I/O error during system call, Software caused connection abort.',
    );

    expect(AuthSessionService.isTransientAuthFailure(networkAbort), isTrue);
    expect(AuthSessionService.isDisabledAuthFailure(networkAbort), isFalse);

    final disabled = FirebaseAuthException(code: 'user-disabled');

    expect(AuthSessionService.isDisabledAuthFailure(disabled), isTrue);
    expect(AuthSessionService.isTransientAuthFailure(disabled), isFalse);
  });
}
