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

// Controllers & services
import 'controller/auth_controller.dart';
import 'controller/offre_controller.dart';
import 'controller/user_controller.dart';
import 'controller/follow_controller.dart';
import 'widgets/video_manager.dart';
import 'services/email_link_handler.dart';
import 'services/notifications.dart';

// UI
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/reset_password_screen.dart';

// Theme
import 'theme/app_theme.dart';
import 'theme/ad_colors.dart';

/// Notifications en arrière-plan (isolate)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // ⚠️ Pas d’await long ici
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Barre de statut
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    // Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseAuth.instance.setLanguageCode('fr');

    // FCM Web
    if (kIsWeb) {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    }

    // Notifications
    await NotificationService.initLocal();
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    }
    NotificationService.listenForeground();

    // Injection GetX (ordre critique)
    Get.put<VideoManager>(VideoManager(), permanent: true);
    Get.put<AuthController>(AuthController(), permanent: true);
    Get.put<OffreController>(OffreController(), permanent: true);
    Get.put<UserController>(UserController(), permanent: true);
    Get.put<FollowController>(FollowController(), permanent: true);

    // Rafraîchit le profil réseau (silencieux)
    unawaited(Get.find<VideoManager>().refreshNetworkProfile());

    // Email link handler
    try {
      await EmailLinkHandler.init();
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('EmailLinkHandler init error: $e\n$st');
      }
    }

    // Flutter error handling
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }
    };

    runApp(const MyApp());
  }, (error, stack) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('Uncaught zone error: $error\n$stack');
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
      navigatorKey: Get.key,
      theme: AppTheme.light(),
      defaultTransition: Transition.fadeIn,
      color: AdColors.brand,

      /// Wrapper global SAFE
      builder: (context, child) {
        final Widget safeChild = child ?? const SizedBox.shrink();

        // Fermer clavier au tap
        final wrapped = GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: () {
            final focus = FocusManager.instance.primaryFocus;
            if (focus?.hasFocus == true) focus?.unfocus();
          },
          child: safeChild,
        );

        // MediaQuery SAFE (FIX du trait noir)
        final mq = MediaQuery.of(context);

        final scaleValue =
            mq.textScaler.scale(1.0).clamp(0.85, 1.15);

        final mediaWrapped = MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(scaleValue),
            padding: mq.padding,
            viewPadding: mq.viewPadding,
            viewInsets: mq.viewInsets,
            systemGestureInsets: mq.systemGestureInsets,
          ),
          child: wrapped,
        );

        return ScrollConfiguration(
          behavior: const _AppScrollBehavior(),
          child: mediaWrapped,
        );
      },

      // Page initiale
      home: const SplashScreen(),

      // Routes GetX
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/login', page: () => const LoginScreen()),
        GetPage(name: '/main', page: () => const MainScreen()),
        GetPage(name: '/verify', page: () => const VerifyEmailScreen()),
        GetPage(
          name: '/reset',
          page: () {
            final args = Get.arguments as Map<String, dynamic>?;
            final oobCode = args?['oobCode'] ?? '';
            return ResetPasswordScreen(oobCode: oobCode);
          },
        ),
      ],
    );
  }
}

/// Scroll behavior custom
class _AppScrollBehavior extends ScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS) {
      return const BouncingScrollPhysics();
    }
    return const ClampingScrollPhysics();
  }
}
