import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
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

    // Hard dependencies: the app genuinely cannot run without these, so
    // they're allowed to propagate and abort startup (reportZoneError still
    // captures and logs the failure remotely).
    await FirebaseBootstrap.initialize();
    await AppCheckService.initialize();
    AppBindings.registerPermanentDependencies();

    // Everything below is best-effort: a failure here must never prevent
    // runApp() from ever executing, which would otherwise strand the user
    // on a blank/native splash screen forever with no way to recover.
    await _runNonCritical(
      'FirebaseAuth.setLanguageCode',
      () async => FirebaseAuth.instance.setLanguageCode('fr'),
    );

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

    _safeReportError(
      'Uncaught zone error',
      source: 'AppBootstrap.reportZoneError',
      error: error,
      stackTrace: stack,
    );
  }

  // Reporting itself must never throw: this can run before Firebase is
  // initialized (e.g. errors during the bootstrap sequence), and
  // AppLogger.error transitively touches FirebaseFunctions.instanceFor,
  // which throws if called before Firebase.initializeApp() has resolved.
  static void _safeReportError(
    String message, {
    required String source,
    required Object error,
    StackTrace? stackTrace,
  }) {
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

  static void _configureFlutterErrors() {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }
      _safeReportError(
        'Uncaught Flutter framework error',
        source: 'FlutterError.onError',
        error: details.exception,
        stackTrace: details.stack,
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _safeReportError(
        'Uncaught platform error',
        source: 'PlatformDispatcher.onError',
        error: error,
        stackTrace: stack,
      );
      return true;
    };
  }
}
