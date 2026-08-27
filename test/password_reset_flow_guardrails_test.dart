import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// A tapped "mot de passe oublié" link opens the app, not a browser.
///
/// The link Firebase mails points at `<authDomain>/__/auth/action`, and
/// AndroidManifest.xml claims that path as a verified App Link. So the reset
/// happens on [ResetPasswordScreen] — and three separate defects meant it
/// usually did not happen at all: the screen was taken away before a password
/// could be typed, the link was dropped entirely after a sign-out, and a
/// refused code failed in silence.
void main() {
  group('the reset screen survives the cold start it is opened by', () {
    // SplashScreen and UserController both resolve the session and call
    // offAllNamed during the launch a tapped link produces. Whichever landed
    // last won, and it was rarely the reset screen: the app "opened directly"
    // on login or on the feed instead.
    test('the flow is claimed before the code is verified', () {
      final handler = _read('lib/services/email_link_handler.dart');

      final claim = handler.indexOf('PasswordResetFlow.begin();');
      final verify = handler.indexOf('verifyPasswordResetCode(oob)');
      expect(claim, isNonNegative);
      expect(verify, isNonNegative);
      expect(
        claim,
        lessThan(verify),
        reason: 'the network round-trip is where the race is lost',
      );
    });

    // A push landed on top of the splash route, so the first offAllNamed from
    // either owner replaced it — and back from the reset screen returned to a
    // splash that immediately re-resolved the session.
    test('the screen replaces the stack rather than sitting on top of it', () {
      final handler = _read('lib/services/email_link_handler.dart');

      expect(handler, contains('Get.offAllNamed(\n          AppRoutes.resetPassword'));
      expect(
        handler,
        isNot(contains('Get.toNamed(\n            AppRoutes.resetPassword')),
        reason: 'a pushed reset screen is a replaceable one',
      );
    });

    test('session routing stands down while a reset is in progress', () {
      final controller = _read('lib/controller/user_controller.dart');
      final splash = _read('lib/screens/splash_screen.dart');

      // Inside _safeOffAllNamed, so the queued route drained in its `finally`
      // is covered too — that is how the losing navigation usually arrived.
      final guard = controller.indexOf(
        'if (PasswordResetFlow.isInProgress && route != AppRoutes.resetPassword)',
      );
      final navigator = controller.indexOf('Get.offAllNamed(route');
      expect(guard, isNonNegative);
      expect(navigator, isNonNegative);
      expect(guard, lessThan(navigator));

      expect(splash, contains('if (PasswordResetFlow.isInProgress)'));
    });

    // The latch must never become a trap: every exit releases it first, and
    // it expires on its own if none of them runs.
    test('every exit from the screen releases the flow', () {
      final screen = _read('lib/screens/reset_password_screen.dart');
      final flow = _read('lib/services/auth/password_reset_flow.dart');

      expect(screen, contains('Future<void> _leaveToLogin('));
      expect(screen, contains('PasswordResetFlow.end();\n    await Get.offAllNamed(AppRoutes.login'));
      expect(
        screen,
        isNot(contains('onPressed: () => Get.offAllNamed(AppRoutes.login)')),
        reason: 'leaving without releasing the flow mutes session routing',
      );
      // Back has nothing to pop to once the stack was replaced.
      expect(screen, contains('PopScope('));
      expect(screen, contains('canPop: false'));
      expect(flow, contains('static const Duration _maxDuration'));
      expect(flow, contains('_startedAt = null;'));

      // And if the screen was never installed, nothing downstream can
      // release the flow — so the hand-off releases it itself rather than
      // muting session routing with no screen to justify it.
      final handler = _read('lib/services/email_link_handler.dart');
      expect(handler, contains('if (!opened) {'));
      final failed = handler.indexOf('if (!opened) {');
      expect(
        handler.substring(failed, failed + 400),
        contains('PasswordResetFlow.end();'),
      );
    });
  });

  group('the link is not dropped, and failures are not silent', () {
    // Sign-out cancelled the app-link subscription and nothing re-armed it,
    // so a link tapped afterwards reached a deaf app — exactly the state a
    // user is in when they need a reset.
    test('signing out keeps the app listening for links', () {
      final auth = _read('lib/controller/auth_controller.dart');
      final handler = _read('lib/services/email_link_handler.dart');

      expect(auth, contains('EmailLinkHandler.resetForNewSession()'));
      expect(
        auth,
        isNot(contains('await EmailLinkHandler.dispose()')),
        reason: 'disposing here left the process with no link listener',
      );
      expect(handler, contains('static void resetForNewSession()'));
      // dispose() stays for real teardown (widget_test calls it).
      expect(handler, contains('static Future<void> dispose() async'));
    });

    // An expired or already-used link returned false and nothing else: the
    // app opened on login with no hint that the link was the reason.
    test('a refused code explains itself on the login screen', () {
      final handler = _read('lib/services/email_link_handler.dart');

      expect(handler, contains('_openLoginWithNotice('));
      expect(handler, contains("'sessionNoticeTitle': title"));
      expect(handler, contains("title: 'Lien de réinitialisation refusé'"));
      // A network refusal must not burn the link for a second tap.
      expect(handler, contains('_handledOobCodes.remove(oob);'));
    });

    // _logDebug is gated by kDebugMode AND by AppLogger dropping the debug
    // level outright, so in a release build it wrote nowhere: a reset link
    // that stopped working left no trace on screen or in the client log.
    test('link failures are recorded at a level release builds keep', () {
      final handler = _read('lib/services/email_link_handler.dart');

      expect(handler, contains('static void _logIssue('));
      expect(handler, contains("source: 'email_link_handler'"));
      expect(handler, contains('AppLogger.warning('));
      for (final failure in const <String>[
        "'resetPassword link refused",
        "_logIssue('resetPassword link failed unexpectedly'",
        "_logIssue('verifyEmail link refused",
        "_logIssue('gave up waiting for a navigator",
      ]) {
        expect(handler, contains(failure));
      }
    });

    // AppBootstrap.initialize() finishes before runApp, so on the cold start
    // a tapped link produces there is no navigator yet. The old code guessed
    // 300 ms and navigated blind.
    test('navigation waits for a navigator instead of guessing', () {
      final handler = _read('lib/services/email_link_handler.dart');

      expect(handler, contains('static Future<bool> _navigateWhenReady('));
      expect(handler, contains('Get.key.currentState != null'));
      expect(
        handler,
        isNot(contains('Future.delayed(const Duration(milliseconds: 300)')),
      );
    });

    // The reset screen owns a spinner cleared in a `finally`; unbounded, the
    // call left "Valider" spinning with no error and no way to retry.
    test('applying the new password is bounded like its siblings', () {
      final service = _read('lib/services/auth/auth_session_service.dart');

      expect(
        service,
        contains("return _bounded(confirm, 'changement du mot de passe');"),
      );
      // The raw call still exists — inside the bounded closure, which is
      // the point. What must not come back is calling it as the method body.
      final confirm = service.indexOf('Future<void> confirmPasswordReset({');
      expect(confirm, isNonNegative);
      final body = service.substring(confirm, confirm + 400);
      expect(body, contains('Future<void> confirm() {'));
      expect(body, contains('_bounded(confirm,'));
    });
  });

  group('the screen names the account it is changing', () {
    test('the verified address reaches the screen', () {
      final handler = _read('lib/services/email_link_handler.dart');
      final routes = _read('lib/config/app_routes.dart');
      final screen = _read('lib/screens/reset_password_screen.dart');

      expect(handler, contains("final email = await FirebaseAuth.instance"));
      expect(handler, contains("if (email.trim().isNotEmpty) 'email'"));
      expect(routes, contains('static String? _resolveResetPasswordEmail()'));
      expect(routes, contains('accountEmail: _resolveResetPasswordEmail()'));
      expect(screen, contains('final String? accountEmail;'));
      expect(screen, contains("'Compte : \${widget.accountEmail!.trim()}'"));
      // Firebase revokes the old sessions on a password change, so login is
      // always next; carry the address so it is not retyped.
      expect(screen, contains("'prefillEmail': email"));
    });
  });
}
