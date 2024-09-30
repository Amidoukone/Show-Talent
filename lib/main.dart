import 'package:get/get.dart';
import 'package:show_talent/screens/main_screen.dart';
import 'package:show_talent/screens/splash_screen.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

// Importation des contrôleurs
import 'controller/auth_controller.dart';
import 'controller/offre_controller.dart';
import 'controller/notification_controller.dart';
import 'controller/user_controller.dart';  // Ajout du UserController

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisation de Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Injection des contrôleurs avant l'application
  Get.put(AuthController());   // Gestion de l'authentification
  Get.put(OffreController());  // Gestion des offres
  Get.put(NotificationController());  // Gestion des notifications
  Get.put(UserController());  // Gestion des utilisateurs (important pour l'utilisateur connecté)

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'ShowTalent',
      theme: ThemeData(
        primaryColor: const Color.fromARGB(255, 11, 78, 72),
        scaffoldBackgroundColor: const Color.fromARGB(255, 219, 239, 240),

        // Thème pour le BottomNavigationBar
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF004d00),
          selectedItemColor: Color.fromARGB(255, 202, 229, 236),
          unselectedItemColor: Color(0xFF8AB98A),
        ),
      ),
      home: const SplashScreen(),  // Écran de démarrage
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),  // Splash screen
        GetPage(name: '/main', page: () => const MainScreen()),  // Page principale après Splash
      ],
    );
  }
}
