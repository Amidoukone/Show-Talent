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

//  Controllers & services
import 'controller/auth_controller.dart';
import 'controller/offre_controller.dart';
import 'controller/user_controller.dart';
import 'controller/follow_controller.dart';
import 'widgets/video_manager.dart';
import 'services/email_link_handler.dart';
import 'services/notifications.dart';
import 'videos/domain/network_profile.dart';

//  UI
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/reset_password_screen.dart'; // ✅ Ajout pour gestion reset password

//  Theme
import 'theme/app_theme.dart';
import 'theme/ad_colors.dart';

///  Notifications en arrière-plan (isolate) — uniquement hors Web
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  //  Ici tu peux ajouter un log léger ou un enregistrement analytique :
  // Exemple : NotificationService.logBackgroundMessage(message);
  // Ce bloc ne doit pas bloquer, donc aucun await long ici.
}

Future<void> main() async {
  //  Zone sécurisée pour capturer toutes les erreurs non gérées
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Optionnel : verrouille l’orientation portrait si nécessaire
    // await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // Barre de statut transparente et lisible
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    //  Initialisation Firebase
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseAuth.instance.setLanguageCode('fr');

    //  Empêche l’auto-init FCM sur Web
    if (kIsWeb) {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    }

    //  Notifications locales et foreground
    await NotificationService.initLocal();
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
    NotificationService.listenForeground();

    //  Injection GetX (ordre important)
    Get.put<VideoManager>(VideoManager(), permanent: true);
    Get.put<AuthController>(AuthController(), permanent: true);
    Get.put<OffreController>(OffreController(), permanent: true);
    Get.put<UserController>(UserController(), permanent: true);
    Get.put<FollowController>(FollowController(), permanent: true);

    // ✅ Rafraîchit le profil réseau sans bloquer le démarrage
    unawaited(Get.find<VideoManager>().refreshNetworkProfile());

    //  Gestion des liens d’authentification par e-mail
    try {
      await EmailLinkHandler.init();
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('EmailLinkHandler init error: $e\n$st');
      }
      // En production, ignorer sans bloquer
    }

    //  Gestion des erreurs Flutter (UI thread)
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      } else {
        //  En production, envoie aux crash logs Firebase
        // await FirebaseCrashlytics.instance.recordFlutterError(details);
      }
    };

    //  Lancement de l’application
    runApp(const MyApp());
  }, (error, stack) async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('Uncaught zone error: $error\n$stack');
    } else {
      //  En production, log des erreurs non capturées
      // await FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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

      //  Wrapper global : gestion focus, scroll et accessibilité
      builder: (context, child) {
        // Ferme le clavier sur tap hors champ
        final wrapped = GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: () {
            final focus = FocusManager.instance.primaryFocus;
            if (focus?.hasFocus == true) focus?.unfocus();
          },
          child: child,
        );

        //  Correction définitive du warning et du bug sur TextScaler
        final currentScaler = MediaQuery.of(context).textScaler;
        final scaleValue = currentScaler.scale(1.0).clamp(0.85, 1.15);
        final clampedScaler = TextScaler.linear(scaleValue);

        final content = ScrollConfiguration(
          behavior: const _AppScrollBehavior(),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: clampedScaler),
            child: wrapped,
          ),
        );

        // ✅ Overlay debug pour voir le profil réseau en temps réel (uniquement en debug)
        if (!kDebugMode || !Get.isRegistered<VideoManager>()) return content;

        final videoManager = Get.find<VideoManager>();
        return ValueListenableBuilder<NetworkProfile?>(
          valueListenable: videoManager.profileNotifier,
          builder: (context, profile, _) {
            if (profile == null) return content;

            final buffer = StringBuffer('Profil réseau : ${profile.tier.name}');
            if (profile.measuredKbps != null) {
              buffer.write(' ~${profile.measuredKbps!.toStringAsFixed(0)} kbps');
            }
            if (!profile.hasConnection) buffer.write(' (offline)');

            return Stack(
              children: [
                content,
                Positioned(
                  left: 12,
                  top: 12,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: _NetworkProfileDebugText(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },

      // Page initiale
      home: const SplashScreen(),

      // ✅ Routes GetX
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/login', page: () => const LoginScreen()),
        GetPage(name: '/main', page: () => const MainScreen()),
        GetPage(name: '/verify', page: () => const VerifyEmailScreen()),

        // ✅ Nouvelle route pour réinitialisation du mot de passe
        GetPage(
          name: '/reset',
          page: () {
            // Récupère le oobCode transmis par Get.arguments (depuis EmailLinkHandler)
            final args = Get.arguments as Map<String, dynamic>?;
            final oobCode = args?['oobCode'] ?? '';
            return ResetPasswordScreen(oobCode: oobCode);
          },
        ),
      ],

      color: AdColors.brand,
    );
  }
}

/// Petit widget séparé pour éviter de reconstruire du texte/style inutilement.
/// (Le texte réel est recalculé dans le builder ci-dessus)
class _NetworkProfileDebugText extends StatelessWidget {
  const _NetworkProfileDebugText();

  @override
  Widget build(BuildContext context) {
    // Le texte est injecté via le Stack builder.
    // Ici on met un style stable.
    return Text(
      '',
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Comportement de scroll custom : pas de glow, inerties natives.
class _AppScrollBehavior extends ScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // Supprime le glow
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // Bouncing pour iOS, Clamping pour Android
    if (Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.macOS) {
      return const BouncingScrollPhysics();
    }
    return const ClampingScrollPhysics();
  }
}
