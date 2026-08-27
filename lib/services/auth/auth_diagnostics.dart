import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../app_logger.dart';

/// Reports the authentication failures a user is standing in front of.
///
/// Two gaps made these failures invisible in production, and each one alone
/// was enough to hide them.
///
/// **The level.** Every failure path in the auth flow logged through
/// `AppLogger.debug`, and `AppLogger._shouldSendToRemote` drops `debug`
/// unconditionally. In a release build those calls wrote nowhere at all: a
/// tester bounced back to the login screen left no trace anywhere.
///
/// **The sink.** Raising the level is not enough on its own. The remote log
/// goes to the `logClientEvents` callable, which starts with `requireAuth` —
/// so it rejects any caller without a session. That is exactly the caller
/// these reports come from: a failed sign-in, a refused reset link, a session
/// resolution that ended in a sign-out. The one sink we had was unreachable
/// precisely when it mattered.
///
/// So this reports to both, and neither can hide a failure on its own:
///
/// * `AppLogger` keeps the internal record whenever there *is* a session, and
///   stays the searchable history in `client_logs`;
/// * Crashlytics takes the same report as a **non-fatal**, needs no Firebase
///   Auth session, and is therefore the one that still works when the user is
///   signed out.
///
/// Non-fatal is deliberate. These are handled failures — the app recovered,
/// showed a message, or sent the user somewhere safe. Booking them as fatal
/// would wreck the crash-free-users metric that `AppBootstrap` is careful to
/// keep meaningful, and would drown the genuinely fatal reports.
class AuthDiagnostics {
  AuthDiagnostics._();

  /// A failure that left the user stuck, ejected, or bounced.
  ///
  /// [stage] is the flow this happened in — `session_resolve`,
  /// `splash_fallback`, `route_from_auth`. It becomes the Crashlytics
  /// grouping key, so keep it stable and coarse: one stage per place a user
  /// can get stuck, not one per call site.
  static void failure(
    String message, {
    required String stage,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _report(message, stage: stage, error: error, stackTrace: stackTrace,
        fatalToUser: true);
  }

  /// A failure the app absorbed — a retry is coming, or the session stands.
  ///
  /// Sampled rather than certain: these are frequent on a weak network and
  /// individually uninteresting. What matters is the rate.
  static void handled(
    String message, {
    required String stage,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _report(message, stage: stage, error: error, stackTrace: stackTrace,
        fatalToUser: false);
  }

  static void _report(
    String message, {
    required String stage,
    required bool fatalToUser,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final source = 'auth/$stage';

    // Reporting must never become the incident. AppLogger reaches
    // FirebaseFunctions, which throws if Firebase has not finished starting —
    // and some of these failures happen during bootstrap.
    try {
      if (fatalToUser) {
        AppLogger.error(
          message,
          source: source,
          error: error,
          stackTrace: stackTrace,
        );
      } else {
        AppLogger.warning(
          message,
          source: source,
          error: error,
          stackTrace: stackTrace,
        );
      }
    } catch (_) {
      // Best-effort only; never let the reporter mask what it is reporting.
    }

    if (kIsWeb) {
      return;
    }

    try {
      // Swallow the outcome rather than `unawaited` it: a rejection from the
      // reporter would otherwise reach the zone handler, which reports it,
      // which fails the same way. AppBootstrap._reportSilently makes the same
      // point about the same call.
      FirebaseCrashlytics.instance
          .recordError(
            error ?? message,
            stackTrace,
            reason: '$source: $message',
            fatal: false,
          )
          .catchError((Object _) {});
    } catch (_) {
      // Crashlytics may not be ready yet — a failure during bootstrap itself.
    }
  }
}
