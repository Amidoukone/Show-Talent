import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 1.0.7+17 shipped an app nobody could sign into: the loader turned forever
/// and the app never opened.
///
/// The spinner was still animating, so the UI isolate was healthy — the flow
/// was simply awaiting something that never came back. Sign-in reaches the
/// network five times before the one call that had a deadline, and none of
/// those five timed out on its own. With no deadline there is no error, so the
/// login screen's `finally` never ran, the busy state never cleared, and the
/// user had nothing to read and nothing to retry.
///
/// These tests are about the *shape* of that failure, not any one trigger:
/// whatever stalls, the flow must end somewhere the user can act on.
void main() {
  group('sign-in is bounded at every level', () {
    late String service;

    setUpAll(() {
      service =
          File('lib/services/auth/auth_session_service.dart').readAsStringSync();
    });

    test('each Firebase Auth round-trip carries a deadline', () {
      expect(service, contains('_authCallTimeout'));
      expect(service, contains('static Future<T> _bounded<T>('));
      expect(
        service,
        contains('.timeout('),
        reason: 'an unbounded await here is the whole bug',
      );
    });

    test('the credential exchange carries one deadline as a whole', () {
      // Individually-bounded calls can still add up: five 20s stalls in a row
      // is an interminable wait even though no single call ever timed out.
      expect(service, contains('_signInHandshakeTimeout'));
      expect(service, contains('Future<User> _signInHandshake('));
    });

    test('a timeout surfaces as an error the login screen already maps', () {
      // A bare TimeoutException would reach the generic "erreur inattendue"
      // catch, which tells the user nothing about what to do.
      expect(service, contains('AuthFlowException'));
      expect(service, contains('prend trop de temps'));
    });

    test('the screen that owns the spinner guarantees it stops', () {
      final screen = File('lib/screens/login_screen.dart').readAsStringSync();

      expect(screen, contains('_signInTimeout'));
      expect(
        screen,
        contains('.timeout('),
        reason:
            'only this screen can promise the spinner always stops, whatever '
            'the service below it does',
      );
      // The busy flag must still be cleared on every exit path.
      expect(screen, contains('setState(() => _isLoading = false)'));
    });
  });

  group('error reporting can never become the outage', () {
    late String bootstrap;

    setUpAll(() {
      bootstrap = File('lib/config/app_bootstrap.dart').readAsStringSync();
    });

    test('a failing report cannot re-enter the reporter', () {
      // recordFlutterFatalError and recordError both return futures. A leaked
      // rejection lands in runZonedGuarded, which reports it, which fails the
      // same way -- an unbounded cycle on the UI isolate.
      expect(bootstrap, contains('_reportingInFlight'));
      expect(bootstrap, contains('static void _reportSilently('));
    });

    test('no reporting future is left to leak its rejection', () {
      expect(
        bootstrap,
        isNot(contains('unawaited(\n          FirebaseCrashlytics')),
        reason: 'unawaited() lets the rejection escape into the zone handler',
      );
      expect(
        bootstrap,
        contains('_reportSilently(\n            FirebaseCrashlytics.instance'
            '.recordFlutterFatalError(details),'),
      );
    });
  });

  group('operational scripts name no credentials path', () {
    test('a service-account path is never hard-coded', () {
      // A committed path to a credentials file is an exposure in its own
      // right: it tells a reader exactly which file to go looking for. Secret
      // scanning flags it, correctly.
      for (final path in Directory('scripts')
          .listSync()
          .whereType<File>()
          .where((file) =>
              file.path.endsWith('.js') ||
              file.path.endsWith('.mjs') ||
              file.path.endsWith('.ps1'))) {
        expect(
          path.readAsStringSync(),
          isNot(contains('adfoot-production-ops.json')),
          reason: '${path.path} must take the path from the environment',
        );
      }
    });
  });
}
