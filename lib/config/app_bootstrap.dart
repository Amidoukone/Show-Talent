import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_check_service.dart';
import '../services/email_link_handler.dart';
import '../services/notifications.dart';
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

    await FirebaseBootstrap.initialize();
    await AppCheckService.initialize();
    FirebaseAuth.instance.setLanguageCode('fr');

    if (kIsWeb) {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    }

    await NotificationService.initLocal();
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );
    }
    NotificationService.listenForeground();

    AppBindings.registerPermanentDependencies();
    AppBindings.warmUpBackgroundServices();

    await _initializeEmailLinkHandler();
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
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
  }

  static Future<void> _initializeEmailLinkHandler() async {
    try {
      await EmailLinkHandler.init();
    } catch (error, stack) {
      if (!kDebugMode) {
        return;
      }

      AppLogger.debug('EmailLinkHandler init error: $error\n$stack');
    }
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
