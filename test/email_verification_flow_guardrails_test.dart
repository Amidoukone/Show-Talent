import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Email verification flow guardrails', () {
    test('auth session refreshes the ID token before syncing verified users',
        () {
      final content = File('lib/services/auth/auth_session_service.dart')
          .readAsStringSync();

      expect(content, contains('await refreshed.getIdToken(true);'));
      expect(
          content, contains('await _refreshVerifiedUserIdToken(refreshed);'));
      expect(content, contains('markEmailVerifiedAndActivate('));
      expect(content, contains("httpsCallable('completeEmailVerification')"));
      expect(content, contains('_retryEmailVerificationSync('));
    });

    test('auth session prefers callable sync before local Firestore fallback',
        () {
      final content = File('lib/services/auth/auth_session_service.dart')
          .readAsStringSync();

      final callableIndex =
          content.indexOf('await _completeEmailVerificationViaCallable(');
      final localWriteIndex = content
          .indexOf('await _userRepository.markEmailVerifiedAndActivate(');

      expect(callableIndex, isNonNegative);
      expect(localWriteIndex, isNonNegative);
      expect(callableIndex, lessThan(localWriteIndex));
      expect(content, contains("error.code != 'permission-denied'"));
    });

    test(
        'resolve session retries backend verification sync before leaving the user on verify email',
        () {
      final content = File('lib/services/auth/auth_session_service.dart')
          .readAsStringSync();

      expect(content,
          contains('final syncedUser = await _retryEmailVerificationSync('));
      expect(content, contains('destination: AuthSessionDestination.main,'));
      expect(content,
          contains('destination: AuthSessionDestination.verifyEmail,'));
    });

    test('verify email screen still redirects to login after verification', () {
      final content =
          File('lib/screens/verify_email_screen.dart').readAsStringSync();

      expect(content, contains('_redirectToLogin('));
      expect(content, contains("'sessionNoticeTitle': 'E-mail verifie'"));
      expect(content, contains('Get.offAllNamed('));
      expect(content, contains('EmailActionLinkParser.extract(Uri.base)'));
    });

    test('verify email screen now sends users back to login explicitly', () {
      final content =
          File('lib/screens/verify_email_screen.dart').readAsStringSync();

      expect(content, contains('Retour a la connexion'));
      expect(content, contains('_goBackToLogin'));
      expect(content, contains('_loginAfterVerificationMessage'));
      expect(content, isNot(contains('J\\\'ai clique sur le lien, continuer')));
    });

    test('email verification sending uses app-aware action code settings', () {
      final content = File('lib/services/auth/auth_session_service.dart')
          .readAsStringSync();
      final environment =
          File('lib/config/app_environment.dart').readAsStringSync();

      expect(content, contains('_defaultEmailVerificationActionCodeSettings'));
      expect(content, contains('await user.sendEmailVerification('));
      expect(
        environment,
        contains('buildEmailVerificationActionCodeSettings()'),
      );
      expect(environment, contains('emailVerificationActionUrl'));
    });

    test('password reset sending uses app-aware action code settings', () {
      final content = File('lib/services/auth/auth_session_service.dart')
          .readAsStringSync();
      final environment =
          File('lib/config/app_environment.dart').readAsStringSync();

      expect(content, contains('_defaultPasswordResetActionCodeSettings'));
      expect(content, contains('return _auth.sendPasswordResetEmail('));
      expect(
        environment,
        contains('buildPasswordResetActionCodeSettings()'),
      );
      expect(environment, contains('passwordResetActionUrl'));
    });

    test('email link parsing handles nested Firebase redirects', () {
      final parser =
          File('lib/utils/email_action_link_parser.dart').readAsStringSync();
      final emailHandler =
          File('lib/services/email_link_handler.dart').readAsStringSync();

      expect(parser, contains("'continueUrl'"));
      expect(parser, contains("'deep_link_id'"));
      expect(emailHandler, contains('EmailActionLinkParser.extract(link)'));
    });

    test('account verification callable cleans legacy profile block fields',
        () {
      final content = File('functions/src/account_verification_actions.ts')
          .readAsStringSync();

      expect(content, contains('estBloque: fieldValue.delete()'));
      expect(content, contains('blockedReason: fieldValue.delete()'));
      expect(content, contains('blockMode: fieldValue.delete()'));
    });
  });
}
