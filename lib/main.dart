import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Importation des écrans
import 'package:show_talent/screens/main_screen.dart';
import 'package:show_talent/screens/splash_screen.dart';

// Importation des contrôleurs
import 'controller/auth_controller.dart';
import 'controller/offre_controller.dart';
import 'controller/notification_controller.dart';
import 'controller/user_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisation de Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Injection des contrôleurs avant le démarrage de l'application
  Get.put(AuthController());
  Get.put(OffreController());
  Get.put(NotificationController());
  Get.put(UserController());

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
        primaryColor: const Color(0xFF214D4F), // Couleur principale de l'application
        scaffoldBackgroundColor: const Color(0xFFE6EEFA), // Couleur de fond

        // Thème pour AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF214D4F),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(
            color: Colors.white, // Couleur des icônes
          ),
        ),

        // Thème pour les boutons "ElevatedButton"
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF214D4F), // Couleur des boutons
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

        // Thème des champs de texte (TextField)
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

        // Thème pour la barre de navigation inférieure
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF214D4F),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
        ),

        // Thème global pour le texte
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16, color: Color(0xFF214D4F)),
          bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF214D4F)),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF214D4F)),
          titleSmall: TextStyle(fontSize: 16, color: Color(0xFF214D4F)),
        ),
      ),
      home: const SplashScreen(),  // Écran de démarrage
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/main', page: () => const MainScreen()),  // Page principale après le splash screen
      ],
    );
  }
}
