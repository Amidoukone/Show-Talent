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
/// Reads `static const Duration <name> = Duration(seconds: n)` out of the
/// source, so the guardrail asserts the *relationship* between the budgets
/// rather than pinning the numbers themselves.
Duration? _durationOf(String source, String name) {
  final match = RegExp(
    'Duration $name = Duration\\((seconds|milliseconds): (\\d+)\\)',
  ).firstMatch(source);
  if (match == null) return null;

  final value = int.parse(match.group(2)!);
  return match.group(1) == 'seconds'
      ? Duration(seconds: value)
      : Duration(milliseconds: value);
}

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

    test('the verified-state repair fits inside the timeout that wraps it', () {
      // The repair reconciles a profile still marked unverified while Firebase
      // Auth says otherwise. It is the only sanctioned path -- Rules keep
      // emailVerified/estActif out of the owner-writable allowlist -- so if it
      // is cut off, the account can never open and can never upload.
      //
      // It used to be budgeted by attempt count: five tries of an 8s callable
      // spaced 2s apart, ~48s, inside a 15s resolve timeout. The timeout won
      // every time, and its onTimeout returns destination `main` with a null
      // profile, which reads as success -- so the repair was abandoned in
      // silence and re-abandoned identically on every later sign-in.
      final budget = _durationOf(service, '_verifiedSyncBudget');
      final resolveTimeout =
          _durationOf(service, '_signInSessionResolveTimeout');
      final callTimeout = _durationOf(service, '_verificationCallableTimeout');

      expect(budget, isNotNull, reason: 'the repair must carry a clock budget');
      expect(resolveTimeout, isNotNull);
      expect(callTimeout, isNotNull);

      expect(
        budget!.inMilliseconds + callTimeout!.inMilliseconds,
        lessThan(resolveTimeout!.inMilliseconds),
        reason:
            'the repair plus one in-flight call must finish before the wrapper '
            'times out, or the repair is cut off with nothing recorded',
      );
    });

    test('the repair retries against a deadline, not a retry count', () {
      expect(service, contains('final deadline = DateTime.now().add('));
      expect(
        service,
        isNot(contains('int attempts = 5')),
        reason: 'a count-based budget cannot be reasoned about against a clock',
      );
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

  group('routing waits for a frame, never for the user', () {
    // `Get.offAllNamed` returns the pushed route's *pop* future: it completes
    // when the user leaves the screen, not when the navigation lands. It was
    // awaited under a ten-second timeout, so every successful navigation held
    // `_navigating` true for ten seconds. The token refresh that follows any
    // sign-in then found the flag set, queued its route rather than being
    // dropped as redundant, and the `finally` replayed it -- a second
    // offAllNamed that rebuilt MainScreen ten seconds after arriving on it.
    // The user saw a profile that failed to load until the app was restarted,
    // and offers and events that disappeared.
    test('the pop future is never awaited', () {
      final controller =
          File('lib/controller/user_controller.dart').readAsStringSync();

      final start = controller.indexOf('Get.offAllNamed(route');
      expect(start, isNonNegative);
      final region = controller.substring(start, start + 900);

      expect(
        region,
        isNot(contains('await (navFuture')),
        reason: 'awaiting the pop future is awaiting the user',
      );
      expect(region, contains('unawaited(navFuture.then('));
      expect(region, contains('WidgetsBinding.instance.endOfFrame'));
    });

    // Reporting a success as a failure is its own defect: client_logs for
    // adfoot-production filled with `navigation timed out for route=/main`
    // written moments after navigations that had worked.
    test('only a navigation that really missed is reported', () {
      final controller =
          File('lib/controller/user_controller.dart').readAsStringSync();

      expect(
        controller,
        isNot(contains("'navigation timed out for route=")),
      );
      expect(
        controller,
        contains("'navigation did not land on route="),
      );
      expect(controller, contains('if (Get.currentRoute != route) {'));
      expect(controller, contains("stage: 'navigate'"));
    });

    // SplashScreen had the same trap and no timeout to end it, so the whole
    // method never returned: `_navigating` stayed true for the life of the
    // screen, its `finally` never ran, and the `catch` in
    // _safeOffAllDestination -- the fallback to a direct page when named
    // routing fails -- was unreachable from the day it was written.
    test('the startup fallback to a direct page is reachable', () {
      final splash =
          File('lib/screens/splash_screen.dart').readAsStringSync();

      expect(splash, isNot(contains('await Get.offAllNamed(routeName);')));
      expect(splash, isNot(contains('await Get.offAll(() => page);')));
      expect(splash, contains('WidgetsBinding.instance.endOfFrame'));
      // Landing is now checked, and a miss is what triggers the fallback.
      expect(splash, contains('if (Get.currentRoute != routeName) {'));
      expect(splash, contains('throw StateError('));
      expect(splash, contains('_safeOffAll(_pageForDestination(destination))'));
    });

    // /main is replaced by itself whenever session routing navigates there
    // with arguments, and ChatController, EventController and OffreController
    // must outlive that or the chat, offers and events tabs go empty for the
    // rest of the session.
    //
    // What actually guarantees it is bootstrap, not the route binding:
    // AppBindings puts all three permanently before runApp, and GetX does not
    // delete a permanent instance when a route is removed. Asserted here
    // because it is the real mechanism -- MainShellBinding's guard sees them
    // already registered and returns without doing anything.
    test('main shell controllers survive the route being replaced', () {
      final bindings = File('lib/config/app_bindings.dart').readAsStringSync();

      expect(bindings, contains('_registerPermanent<ChatController>'));
      expect(bindings, contains('_registerPermanent<EventController>'));
      expect(bindings, contains('_registerPermanent<OffreController>'));
      expect(bindings, contains('Get.put<T>(builder(), permanent: true)'));

      final bootstrap = File('lib/config/app_bootstrap.dart').readAsStringSync();
      expect(
        bootstrap,
        contains('AppBindings.registerPermanentDependencies();'),
        reason: 'the permanent registration is what the shell relies on',
      );
    });

    // The route binding is the cover for bootstrap being reordered or failing
    // before that call. It registers nothing on the normal path, and the
    // comment above it must not claim otherwise -- it used to describe a
    // disposal that permanent instances make impossible.
    test('the shell binding is an honest fallback', () {
      final shell =
          File('lib/config/app_page_bindings.dart').readAsStringSync();

      // fenix is right for the fallback: a lazily built instance really is
      // route-scoped, and without it a disposal would be permanent.
      expect(shell, contains('Get.lazyPut<T>(builder, fenix: true)'));
      expect(shell, contains('if (Get.isRegistered<T>() || Get.isPrepared<T>())'));
      expect(
        shell,
        contains('bootstrap already put a permanent instance here'),
        reason: 'the next reader must not be told this line runs',
      );
    });

    // The wait itself is bounded: this method must never again be the thing
    // that blocks session routing.
    test('the frame wait cannot become a new stall', () {
      final controller =
          File('lib/controller/user_controller.dart').readAsStringSync();

      final start = controller.indexOf('WidgetsBinding.instance.endOfFrame');
      expect(start, isNonNegative);
      expect(
        controller.substring(start, start + 200),
        contains('.timeout('),
      );
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
