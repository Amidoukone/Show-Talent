// lib/main.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';

// 🔧 Controllers & services
import 'controller/auth_controller.dart';
import 'controller/offre_controller.dart';
import 'controller/user_controller.dart';
import 'controller/follow_controller.dart'; // ✅ ajouté pour FollowController
import 'widgets/video_manager.dart';
import 'services/email_link_handler.dart';
import 'services/notifications.dart';

// 🔱 UI
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/verify_email_screen.dart'; // ✅ écran unifié de vérification

// 🎨 Theme
import 'theme/app_theme.dart';
import 'theme/ad_colors.dart';

/// 🔔 Notifications en arrière-plan (isolate) — uniquement hors Web
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // TODO: logs/traitements BG si nécessaire (ne bloque pas)
}

Future<void> main() async {
  /// ✅ Tout est maintenant à l’intérieur de runZonedGuarded (Zone mismatch corrigé)
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized(); // 🟢 déplacé ici

    // (Optionnel) verrouiller l’orientation en portrait
    // await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // Barre de statut lisible sur AppBar brand
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark, // iOS
    ));

    // Init Firebase
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Langue des emails/erreurs Auth
    FirebaseAuth.instance.setLanguageCode('fr');

    // Désactive l’auto-init FCM sur Web pour éviter tout prompt avant login
    if (kIsWeb) {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    }

    // Notifications locales + écoute foreground (safe Web/Mobile)
    await NotificationService.initLocal();
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
    NotificationService.listenForeground();

    // 🧩 Enregistre les controllers critiques (ordre important)
    Get.put<VideoManager>(VideoManager(), permanent: true);
    Get.put<AuthController>(AuthController(), permanent: true);
    Get.put<OffreController>(OffreController(), permanent: true);
    Get.put<UserController>(UserController(), permanent: true);
    Get.put<FollowController>(FollowController(), permanent: true); // ✅ ajouté ici

    // 🔗 Deep links d’auth (adfoot.org/verify?...&oobCode=...)
    try {
      await EmailLinkHandler.init();
    } catch (_) {
      // ne bloque pas le démarrage
    }

    // Garde-fous erreurs : en prod on évite un crash “silencieux”
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      } else {
        // TODO: reporter aux crash logs si nécessaire
      }
    };

    /// ✅ runApp dans la même zone
    runApp(const MyApp());
  }, (error, stack) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('Uncaught zone error: $error\n$stack');
    } else {
      // TODO: reporter aux crash logs si nécessaire
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'AD.FOOT',
      debugShowCheckedModeBanner: false,
      navigatorKey: Get.key, // ✅ sécurité navigation GetX
      theme: AppTheme.light(), // 🎨 thème moderne unifié (Material 3)
      defaultTransition: Transition.fadeIn,
      // Builder global : tap-to-unfocus + scroll sans glow + textScale plafonné
      builder: (context, child) {
        // Tap pour fermer le clavier
        final wrapped = GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: () {
            final focus = FocusManager.instance.primaryFocus;
            if (focus?.hasFocus == true) focus?.unfocus();
          },
          child: child,
        );

        // Supprime l’effet “glow” overscroll & plafonne textScale
        return ScrollConfiguration(
          behavior: const _AppScrollBehavior(),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.of(context).textScaleFactor.clamp(0.85, 1.15),
              ),
            ),
            child: wrapped,
          ),
        );
      },
      // Page initiale (routing réel délégué aux controllers)
      home: const SplashScreen(),
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/login', page: () => const LoginScreen()),
        GetPage(name: '/main', page: () => const MainScreen()),
        GetPage(name: '/verify', page: () => const VerifyEmailScreen()),
      ],
      color: AdColors.brand,
    );
  }
}

/// Comportement de scroll custom : pas de glow, inerties natives.
class _AppScrollBehavior extends ScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child; // pas de glow
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // Conserve une sensation native (bouncing iOS, clamping Android)
    if (Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.macOS) {
      return const BouncingScrollPhysics();
    }
    return const ClampingScrollPhysics();
  }
}
