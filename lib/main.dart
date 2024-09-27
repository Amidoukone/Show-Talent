
import 'package:get/get.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/screens/main_screen.dart';
import 'package:show_talent/screens/splash_screen.dart';

import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisation de Firebase avec les options de plateforme
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialisation de GetX pour la gestion de l'état global
  Get.put(UserController());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'ShowTalent',
      theme: ThemeData(
        primaryColor: const Color.fromARGB(255, 11, 78, 72),  // Couleur principale
        scaffoldBackgroundColor: const Color.fromARGB(255, 219, 239, 240),  // Couleur de fond

        // Thème pour le BottomNavigationBar
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF004d00), // Couleur de fond vert foncé
          selectedItemColor: Colors.white, // Couleur des icônes sélectionnées
          unselectedItemColor: Color(0xFF8AB98A), // Couleur des icônes non sélectionnées
        ),
      ),
      home: const SplashScreen(),  // L'écran de démarrage
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/main', page: () => const MainScreen()),  // Page principale après Splash
      ],
    );
  }
}

