import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_check_service.dart';
import '../services/email_link_handler.dart';
import '../services/notifications.dart';
import '../utils/video_tools.dart';
import 'app_bindings.dart';
import 'firebase_bootstrap.dart';
import 'package:adfoot/services/app_logger.dart';

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseBootstrap.initialize();
}

class AppBootstrap {
  AppBootstrap._();

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    _configureSystemUi();
    _configureFlutterErrors();

    // Hard dependency: the app genuinely cannot run without Firebase, so a
    // final failure is still allowed to propagate and abort startup
    // (reportZoneError still captures and logs it remotely; main() falls
    // back to a retry screen instead of leaving a dead splash screen -- see
    // _initializeFirebaseWithRetry).
    await _initializeFirebaseWithRetry();

    // Never awaited. Activating App Check means a Play Integrity handshake,
    // which on real devices routinely takes many seconds and often fails
    // outright (Play-uncertified handsets, stale Play services, slow
    // networks). Awaiting it here froze the native splash for the whole
    // activation timeout on every cold start before runApp() could run --
    // which is exactly what testers reported as "the loader spins forever".
    // App Check is an anti-abuse signal, not a startup dependency: the app
    // must render and stay usable whether or not a token ever arrives.
    unawaited(AppCheckService.initialize());

    AppBindings.registerPermanentDependencies();

    // Everything below is best-effort: a failure here must never prevent
    // runApp() from ever executing, which would otherwise strand the user
    // on a blank/native splash screen forever with no way to recover.
    await _runNonCritical(
      'FirebaseAuth.setLanguageCode',
      () async => FirebaseAuth.instance.setLanguageCode('fr'),
    );

    if (!kIsWeb) {
      // Off in debug builds so local development doesn't pollute Crashlytics
      // with dev-machine noise; on for every real build (internal test,
      // staging, production) so crashes are finally diagnosable.
      await _runNonCritical(
        'FirebaseCrashlytics.setCrashlyticsCollectionEnabled',
        () => FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
          !kDebugMode,
        ),
      );
    }

    if (kIsWeb) {
      await _runNonCritical(
        'FirebaseMessaging.setAutoInitEnabled',
        () => FirebaseMessaging.instance.setAutoInitEnabled(false),
      );
    }

    await _runNonCritical(
      'NotificationService.initLocal',
      NotificationService.initLocal,
    );

    if (!kIsWeb) {
      await _runNonCritical(
        'FirebaseMessaging.onBackgroundMessage',
        () async => FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        ),
      );
    }

    await _runNonCritical(
      'NotificationService.listenForeground',
      () async => NotificationService.listenForeground(),
    );

    await _runNonCritical(
      'NotificationService.listenTokenRefresh',
      NotificationService.listenTokenRefresh,
    );

    await _runNonCritical(
      'NotificationService.listenNotificationTaps',
      NotificationService.listenNotificationTaps,
    );

    await _runNonCritical(
      'AppBindings.warmUpBackgroundServices',
      () async => AppBindings.warmUpBackgroundServices(),
    );

    // Fire-and-forget: reclaims video-processing temp files orphaned by a
    // previous session getting killed mid-upload (see
    // VideoTools.cleanupStaleTempFiles doc comment). Pure disk cleanup with
    // no UI dependency, so it must not delay runApp().
    unawaited(
      _runNonCritical(
        'VideoTools.cleanupStaleTempFiles',
        VideoTools.cleanupStaleTempFiles,
      ),
    );

    await _initializeEmailLinkHandler();
  }

  // A cold app start with a weak/just-connecting network (the normal case
  // for many testers) can make the very first Firebase.initializeApp() call
  // fail transiently. Previously that single failure aborted startup before
  // runApp() ever ran, which reads to the user as the app closing itself
  // with no error and no way to recover. Retry a few times first --
  // Firebase.initializeApp() is safe to call again (FirebaseBootstrap
  // checks Firebase.apps.isEmpty) -- before letting main() fall back to a
  // retry screen.
  static const int _firebaseInitMaxAttempts = 3;
  static const Duration _firebaseInitRetryDelay = Duration(seconds: 2);

  static Future<void> _initializeFirebaseWithRetry() async {
    for (var attempt = 1; attempt <= _firebaseInitMaxAttempts; attempt++) {
      try {
        await FirebaseBootstrap.initialize();
        return;
      } catch (error, stack) {
        if (attempt >= _firebaseInitMaxAttempts) {
          rethrow;
        }
        if (kDebugMode) {
          AppLogger.debug(
            'FirebaseBootstrap.initialize attempt $attempt failed, '
            'retrying: $error\n$stack',
          );
        }
        await Future.delayed(_firebaseInitRetryDelay * attempt);
      }
    }
  }

  static Future<void> _runNonCritical(
    String step,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error, stack) {
      if (kDebugMode) {
        AppLogger.debug('$step failed (non-blocking): $error\n$stack');
      }
      _safeReportError(
        '$step failed during bootstrap',
        source: 'AppBootstrap.$step',
        error: error,
        stackTrace: stack,
      );
    }
  }

  static void reportZoneError(Object error, StackTrace stack) {
    if (kDebugMode) {
      AppLogger.debug('Uncaught zone error: $error\n$stack');
    }

    // Fatal: nothing caught this. runZonedGuarded is the last line of defence,
    // so anything arriving here already took a user-visible code path down.
    _safeReportError(
      'Uncaught zone error',
      source: 'AppBootstrap.reportZoneError',
      error: error,
      stackTrace: stack,
      fatal: true,
    );
  }

  // Reporting itself must never throw: this can run before Firebase is
  // initialized (e.g. errors during the bootstrap sequence), and
  // AppLogger.error transitively touches FirebaseFunctions.instanceFor,
  // which throws if called before Firebase.initializeApp() has resolved.
  //
  // [fatal] decides whether Crashlytics counts this against the crash-free
  // users metric. It must be true for anything nothing caught (uncaught zone
  // and platform errors) and false for handled failures such as a
  // best-effort bootstrap step: everything used to be reported as non-fatal,
  // which left the Crashlytics dashboard permanently green while the app was
  // in fact dying on users' phones.
  /// Swallows a reporting future's outcome, value and error alike.
  ///
  /// `unawaited()` is the wrong tool here: it documents that nobody waits for
  /// the result, but a rejection still escapes as an unhandled asynchronous
  /// error. Inside an error reporter that is a cycle — the rejection lands in
  /// the zone handler, which reports it, which fails the same way.
  static void _reportSilently(Future<void> future) {
    future.catchError((Object _) {});
  }

  /// True while an error is already being reported.
  ///
  /// Reporting an error must never be able to trigger reporting another one.
  /// Without this, a single reliably-failing Crashlytics or logging call turns
  /// every error into an unbounded recursion that pins the UI isolate: the app
  /// stops progressing without ever crashing, which from the outside looks
  /// exactly like a spinner that never stops.
  static bool _reportingInFlight = false;

  static void _safeReportError(
    String message, {
    required String source,
    required Object error,
    StackTrace? stackTrace,
    bool fatal = false,
    bool reportToCrashlytics = true,
  }) {
    if (_reportingInFlight) {
      return;
    }
    _reportingInFlight = true;

    try {
      try {
        AppLogger.error(
          message,
          source: source,
          error: error,
          stackTrace: stackTrace,
        );
      } catch (_) {
        // Best-effort remote logging only; never let it mask the real error.
      }

      // Additive: AppLogger's own remote log stays the primary internal
      // record. Crashlytics is what turns a previously invisible crash (e.g.
      // the app dying when a phone call interrupts video playback) into a
      // real stack trace we can act on, without replacing the existing log.
      if (!kIsWeb && reportToCrashlytics) {
        try {
          _reportSilently(
            FirebaseCrashlytics.instance.recordError(
              error,
              stackTrace,
              reason: '$source: $message',
              fatal: fatal,
            ),
          );
        } catch (_) {
          // Crashlytics may not be ready yet (e.g. a failure during Firebase
          // bootstrap itself) — never let reporting mask the real error.
        }
      }
    } finally {
      // Synchronous scope only: the guard blocks re-entry *while reporting*,
      // it does not stop the next genuine error from being reported.
      _reportingInFlight = false;
    }
  }

  static void _configureSystemUi() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }

  static Future<void> _initializeEmailLinkHandler() async {
    await _runNonCritical('EmailLinkHandler.init', EmailLinkHandler.init);
  }

  /// True for the errors Flutter raises when an image fails to resolve.
  ///
  /// Matches on the library name the framework stamps on them
  /// (`ImageStreamCompleter.reportError`), which is stable and does not
  /// depend on the exception type — image failures arrive as
  /// `NetworkImageLoadException`, `HttpException`, `SocketException` and
  /// several others depending on where the fetch died.
  static bool _isImageResourceFailure(FlutterErrorDetails details) {
    return details.library == 'image resource service';
  }

  static void _configureFlutterErrors() {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }

      // recordFlutterFatalError, not recordError: this is the hook Crashlytics
      // expects for framework errors, and it is what makes the "crash-free
      // users" metric mean anything. Reporting these as non-fatal kept the
      // dashboard green no matter what happened on the device, which is
      // exactly why the spontaneous crashes users reported were impossible to
      // corroborate.
      //
      // The trade-off is that a recoverable framework error (a RenderFlex
      // overflow, say) now also counts as a crash. That is the right default
      // while the crash picture is still unknown; if the dashboard fills with
      // layout noise later, downgrade *those* specific cases rather than
      // going back to reporting everything as non-fatal.
      // A failed image is not a crash, and it is the single most common
      // framework error this app produces: a profile photo whose Storage
      // object is gone, a thumbnail fetched on a network that dropped, an
      // expired download token. Every one of them reaches here (Flutter
      // reports image failures through FlutterError with
      // `library: 'image resource service'` whenever no error listener is
      // attached), and the two lines below turned each into a *fatal*
      // Crashlytics event plus a remote `logClientEvents` callable.
      //
      // The result was self-reinforcing: the worse the network, the more
      // images failed, the more requests the app fired to report them — and
      // the crash-free-users metric, the whole reason fatal reporting was
      // turned on, was buried under broken avatars.
      //
      // Still recorded, so a genuinely broken asset is visible, but as a
      // non-fatal and without the remote log.
      if (_isImageResourceFailure(details)) {
        if (!kIsWeb) {
          try {
            _reportSilently(
              FirebaseCrashlytics.instance.recordError(
                details.exception,
                details.stack,
                reason: 'FlutterError.onError: image resource failure',
                fatal: false,
              ),
            );
          } catch (_) {
            // Crashlytics may not be ready yet.
          }
        }
        return;
      }

      if (!kIsWeb) {
        // The `try` only catches a *synchronous* throw. recordFlutterFatalError
        // returns a Future, and a bare call leaks its rejection as an unhandled
        // asynchronous error — which runZonedGuarded routes straight back into
        // reportZoneError, into _safeReportError, into another Crashlytics call
        // that fails the same way. That is a self-feeding loop on the UI
        // isolate, and a framework error that repeats every frame (a layout
        // overflow does) is enough to start it. `_reportSilently` is what keeps
        // the reporter from becoming the outage.
        try {
          _reportSilently(
            FirebaseCrashlytics.instance.recordFlutterFatalError(details),
          );
        } catch (_) {
          // Crashlytics may not be initialized yet (an error thrown during
          // bootstrap itself) — never let reporting mask the real error.
        }
      }

      // Kept alongside: AppLogger's remote log stays the primary internal
      // record. Crashlytics is skipped here because the call above already
      // recorded this exact error — reporting it twice would double-count it.
      _safeReportError(
        'Uncaught Flutter framework error',
        source: 'FlutterError.onError',
        error: details.exception,
        stackTrace: details.stack,
        reportToCrashlytics: false,
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      // Reached only when nothing else handled the error, so it is fatal by
      // definition.
      _safeReportError(
        'Uncaught platform error',
        source: 'PlatformDispatcher.onError',
        error: error,
        stackTrace: stack,
        fatal: true,
      );
      return true;
    };
  }
}
