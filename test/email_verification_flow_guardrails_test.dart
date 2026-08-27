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
      // Formatting-insensitive: the callable name may sit on its own line
      // once the argument list wraps. What matters is that the sync still
      // goes through the callable, not that dartfmt kept it on one line.
      expect(content, contains('httpsCallable('));
      expect(content, contains("'completeEmailVerification'"));
      expect(content, contains('HttpsCallableOptions(timeout:'));
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
      expect(content, contains("'sessionNoticeTitle': 'E-mail vérifié'"));
      expect(content, contains('Get.offAllNamed('));
      expect(content, contains('EmailActionLinkParser.extract(Uri.base)'));
    });

    test('verify email screen now sends users back to login explicitly', () {
      final content =
          File('lib/screens/verify_email_screen.dart').readAsStringSync();

      expect(content, contains('Retour à la connexion'));
      expect(content, contains('_goBackToLogin'));
      expect(content, contains('_loginAfterVerificationMessage'));
      expect(content, isNot(contains('J’ai cliqué sur le lien, continuer')));
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

    // The mobile flows pass `<host>/account/reset` and `/account/verify` as
    // their ActionCodeSettings.url -- which is a *continueUrl*: the page
    // Firebase's own action handler forwards to once the code has already
    // been applied, and it forwards without one, because there is nothing
    // left to apply. Treating that as a bad link meant the reward for
    // resetting your password in a browser was a red "Ce lien est invalide
    // ou expiré. Demandez un nouveau lien à l'administration."
    test('landing here with no code is not reported as a broken link', () {
      final script = File('site_pub/auth-action.js').readAsStringSync();

      expect(script, contains('function showMissingCode()'));
      expect(script, contains('if (!oobCode) {'));
      expect(script, contains('showMissingCode();'));
      expect(script, contains('missingCode:'));

      // A link that really was mangled still says so, and so does an
      // expired or reused code -- that one carries an oobCode, reaches
      // Firebase and is refused there with its own message.
      expect(script, contains('if (!apiKey) {'));
      expect(script, contains('copy.invalidLink'));
      expect(
        script,
        isNot(contains('if (!apiKey || !oobCode) {')),
        reason: 'the missing-code case must not share the broken-link branch',
      );
    });

    // The verify path claimed the oobCode before the call and never released
    // it, so a network refusal burned the link: the second tap was dropped
    // as a duplicate, in silence. The reset path already reasoned this way.
    test('a refused verification link can be tapped again', () {
      final handler =
          File('lib/services/email_link_handler.dart').readAsStringSync();

      final start = handler.indexOf("if (mode != 'verifyEmail'");
      expect(start, isNonNegative);
      final end = handler.indexOf(
        'static Future<bool> _handlePasswordResetLink(',
        start,
      );
      expect(end, isNonNegative);

      final verifyBranch = handler.substring(start, end);
      expect(
        RegExp(r'_handledOobCodes\.remove\(oob\);')
            .allMatches(verifyBranch)
            .length,
        2,
        reason: 'both catch blocks have to release the code',
      );
    });

    test('hosting auth action page applies Firebase codes before success', () {
      final script = File('site_pub/auth-action.js').readAsStringSync();
      final resetPage = File('site_pub/reset/index.html').readAsStringSync();
      final verifyPage = File('site_pub/verify/index.html').readAsStringSync();

      expect(script, contains('accounts:update'));
      expect(script, contains('accounts:resetPassword'));
      expect(script, contains('newPassword'));
      expect(script, contains('Opération terminée avec succès.'));
      expect(resetPage, contains('id="reset-form"'));
      expect(resetPage, contains('id="new-password"'));
      expect(resetPage,
          contains('id="success-panel" class="success-panel" hidden'));
      expect(verifyPage, contains('id="action-status"'));
      expect(verifyPage,
          contains('id="success-panel" class="success-panel" hidden'));
      expect(File('site_pub/auth-action.css').readAsStringSync(),
          contains('[hidden]'));
    });
  });
}
