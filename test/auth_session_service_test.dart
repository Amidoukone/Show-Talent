import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/users/user_repository.dart';
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
      UserAccessIssue.blockedOrDisabled.loginMessage,
      contains('bloqué'),
    );
  });
}
