import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The auth flow could fail in production and leave no trace anywhere.
///
/// Two independent gaps, either one enough on its own:
///
/// * every failure path logged through `AppLogger.debug`, and
///   `_shouldSendToRemote` drops `debug` unconditionally — in a release build
///   those calls wrote nowhere at all;
/// * the remote sink is the `logClientEvents` callable, which begins with
///   `requireAuth` — so it rejects exactly the caller these reports come
///   from, a user who is signed out because the auth flow just failed.
void main() {
  group('the reporter reaches a sink that works signed out', () {
    test('it reports to Crashlytics as well as to AppLogger', () {
      final diagnostics = _read('lib/services/auth/auth_diagnostics.dart');

      expect(diagnostics, contains('FirebaseCrashlytics.instance'));
      expect(diagnostics, contains('recordError('));
      expect(diagnostics, contains('AppLogger.error('));
      expect(diagnostics, contains('AppLogger.warning('));
    });

    // These are handled failures: the app recovered, showed a message, or
    // sent the user somewhere safe. Booking them fatal would wreck the
    // crash-free-users metric AppBootstrap is careful to keep meaningful.
    test('handled failures are never booked as fatal', () {
      final diagnostics = _read('lib/services/auth/auth_diagnostics.dart');

      expect(diagnostics, contains('fatal: false'));
      expect(diagnostics, isNot(contains('fatal: true')));
    });

    // Reporting must never become the incident: AppLogger reaches
    // FirebaseFunctions, which throws before Firebase has finished starting,
    // and some of these failures happen during bootstrap.
    test('the reporter cannot throw or reject', () {
      final diagnostics = _read('lib/services/auth/auth_diagnostics.dart');

      expect(diagnostics, contains('.catchError((Object _) {});'));
      expect(diagnostics, contains('} catch (_) {'));
    });

    // The premise of the whole file: verify the sink really does refuse an
    // anonymous caller, so nobody "simplifies" this back to AppLogger alone.
    test('the remote log sink still requires a session', () {
      final actions = _read('functions/src/actions.ts');

      final callable = actions.indexOf('export const logClientEvents = onCall(');
      expect(callable, isNonNegative);
      expect(
        actions.substring(callable, callable + 300),
        contains('await requireAuth(request)'),
      );
    });
  });

  group('the places a user actually gets stuck are reported', () {
    test('a denied access check no longer signs the user out in silence', () {
      final service = _read('lib/services/auth/auth_session_service.dart');

      // Scope the search to resolveSessionSafely: the same guard clause also
      // appears in the verified-user sync, which is a different decision.
      final resolve = service.indexOf(
        'Future<AuthSessionSnapshot> resolveSessionSafely(',
      );
      expect(resolve, isNonNegative);
      final denied = service.indexOf(
        "if (error.code != 'permission-denied')",
        resolve,
      );
      expect(denied, isNonNegative);
      final branch = service.substring(denied, denied + 900);
      expect(branch, contains('AuthDiagnostics.failure('));
      expect(branch, contains("stage: 'session_resolve'"));
      // The report has to come before the sign-out that hides the evidence.
      expect(
        branch.indexOf('AuthDiagnostics.failure('),
        lessThan(branch.indexOf('await signOut();')),
      );
    });

    test('startup, routing, hydration and eviction all report', () {
      final splash = _read('lib/screens/splash_screen.dart');
      final controller = _read('lib/controller/user_controller.dart');
      final auth = _read('lib/controller/auth_controller.dart');

      // "L'application m'a déconnecté au démarrage", previously traceless.
      expect(splash, contains("stage: 'splash_fallback'"));
      // Session routing's last resort: everything dropped, user on login.
      expect(controller, contains("stage: 'route_from_auth'"));
      // The "Profil indisponible" screen with a Réessayer button.
      expect(controller, contains("stage: 'hydrate_profile'"));
      // Access revoked but the eviction itself failed.
      expect(controller, contains("stage: 'force_sign_out'"));
      // Ten seconds for what normally takes one frame.
      expect(controller, contains("stage: 'navigate'"));
      // The stream that drives all of the above. Nothing re-subscribes, so a
      // failure here silently stops the app reacting to auth at all.
      expect(controller, contains("stage: 'auth_stream'"));
      // A security control that stops enforcing: the watcher is dropped and
      // never replaced, so an account disabled later stays inside the app.
      expect(controller, contains("stage: 'access_watch'"));
      // Handled, so sampled rather than certain.
      expect(auth, contains("AuthDiagnostics.handled("));
      expect(auth, contains("stage: 'sync_state'"));
    });

    // _routeFromAuth has three exits and all three do the same visible
    // thing: drop the session, forget the profile, land the user on login.
    // Only the last-resort `catch` was given a report. The two typed
    // branches above it are the ones that actually fire -- a non-transient
    // FirebaseAuthException, and a rules refusal on the access check -- and
    // they still logged at `debug`, which release builds discard.
    test('every branch that ejects the user reports, not just the last', () {
      final controller = _read('lib/controller/user_controller.dart');

      final start = controller.indexOf('Future<void> _routeFromAuth(');
      expect(start, isNonNegative);
      final end = controller.indexOf('void _listenAllUsers()', start);
      expect(end, isNonNegative);

      final method = controller.substring(start, end);
      expect(
        RegExp("stage: 'route_from_auth'").allMatches(method).length,
        3,
        reason: 'each exit that signs the user out has to be visible',
      );
    });

    test('those sites no longer log at a level release builds discard', () {
      final controller = _read('lib/controller/user_controller.dart');
      final splash = _read('lib/screens/splash_screen.dart');

      for (final discarded in const <String>[
        "AppLogger.debug('UserController _routeFromAuth error:",
        "AppLogger.debug('UserController _routeFromAuth auth error:",
        "AppLogger.debug('UserController _routeFromAuth Firebase error:",
        "AppLogger.debug('UserController ensureCurrentUserHydrated error:",
        "AppLogger.debug('UserController forced sign-out error:",
        "AppLogger.debug('UserController navigation timeout",
        "AppLogger.debug('UserController idTokenChanges error:",
        "AppLogger.debug('UserController watchUserAccess error:",
      ]) {
        expect(controller, isNot(contains(discarded)), reason: discarded);
      }

      expect(splash, isNot(contains("AppLogger.debug('Splash fallback error:")));
    });
  });
}
