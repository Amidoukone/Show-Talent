// lib/main.dart
import 'package:adfoot/screens/verify_redirect_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';

// 🔧 Controllers & services
import 'controller/auth_controller.dart';
import 'controller/offre_controller.dart';
import 'controller/user_controller.dart';
import 'widgets/video_manager.dart';
import 'services/email_link_handler.dart';
import 'services/notifications.dart'; // notifs locales + FCM foreground

// 🔱 UI
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

/// 🔔 Notifications en arrière-plan (isolate) — utilisé uniquement hors Web
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Optionnel: logs/traitements BG
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 🌍 Langue des emails/erreurs Auth
  FirebaseAuth.instance.setLanguageCode('fr');

  // 🚫 Désactive l’auto-init FCM sur Web pour éviter tout prompt avant login
  if (kIsWeb) {
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
  }

  // 🔁 Notifications locales (safe Web/Mobile)
  await NotificationService.initLocal();

  // 📬 Handler BG FCM — ⚠️ pas sur Web
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // 🔊 Foreground (affichage local sur mobile, log/discret sur web)
  NotificationService.listenForeground();

  // 🧩 Enregistre les controllers critiques (ordre important)
  Get.put<VideoManager>(VideoManager(), permanent: true);
  Get.put<AuthController>(AuthController(), permanent: true);
  Get.put<OffreController>(OffreController(), permanent: true);
  Get.put<UserController>(UserController(), permanent: true);

  // 🔗 Deep links d’auth (adfoot.org/verify?...&oobCode=...)
  // Mobile: app_links ; Web: géré par VerifyRedirectScreen
  try {
    await EmailLinkHandler.init();
  } catch (_) {
    // ne bloque pas le démarrage si l’init n'est pas pertinente sur la plateforme
  }

  // ❌ IMPORTANT: on ne demande PAS la permission notifications ici.
  // Elle est proposée (soft prompt) après login par AuthController,
  // puis réellement demandée via NotificationService.askPermissionAndUpdateToken().

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'AD.FOOT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF214D4F),
        scaffoldBackgroundColor: const Color(0xFFE6EEFA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF214D4F),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF214D4F),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF214D4F)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF214D4F)),
          ),
          labelStyle: const TextStyle(color: Color(0xFF214D4F)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF214D4F),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16, color: Color(0xFF214D4F)),
          bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF214D4F)),
          titleMedium: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF214D4F),
          ),
        ),
      ),
      // 🧭 Splash — le routing réel est délégué au AuthController
      home: const SplashScreen(),
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/login', page: () => const LoginScreen()),
        GetPage(name: '/main', page: () => const MainScreen()),
        // Route cible du continueUrl: https://adfoot.org/verify
        GetPage(name: '/verify', page: () => const VerifyRedirectScreen()),
      ],
    );
  }
}
