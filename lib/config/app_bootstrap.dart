import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_check_service.dart';
import '../services/email_link_handler.dart';
import '../services/notifications.dart';
import 'app_bindings.dart';
import 'firebase_bootstrap.dart';

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseBootstrap.initialize();
}

class AppBootstrap {
  AppBootstrap._();

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    _configureSystemUi();

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
    _configureFlutterErrors();
  }

  static void reportZoneError(Object error, StackTrace stack) {
    if (!kDebugMode) {
      return;
    }

    debugPrint('Uncaught zone error: $error\n$stack');
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

      debugPrint('EmailLinkHandler init error: $error\n$stack');
    }
  }

  static void _configureFlutterErrors() {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }
    };
  }
}
