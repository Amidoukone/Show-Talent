import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth session destinations map to the shared route table', () {
    expect(AuthSessionDestination.login.routeName, AppRoutes.login);
    expect(
      AuthSessionDestination.verifyEmail.routeName,
      AppRoutes.verifyEmail,
    );
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
    expect(
      UserAccessIssue.disabledAccount.loginMessage,
      contains('desactive'),
    );
  });

  test('transient auth errors are not treated as disabled accounts', () {
    final networkAbort = FirebaseAuthException(
      code: 'network-request-failed',
      message:
          'I/O error during system call, Software caused connection abort.',
    );

    expect(
      AuthSessionService.isTransientAuthFailure(networkAbort),
      isTrue,
    );
    expect(
      AuthSessionService.isDisabledAuthFailure(networkAbort),
      isFalse,
    );

    final disabled = FirebaseAuthException(code: 'user-disabled');

    expect(
      AuthSessionService.isDisabledAuthFailure(disabled),
      isTrue,
    );
    expect(
      AuthSessionService.isTransientAuthFailure(disabled),
      isFalse,
    );
  });
}
