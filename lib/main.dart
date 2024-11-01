import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart'; // Configuration Firebase
import 'controller/auth_controller.dart';
import 'controller/offre_controller.dart';
import 'controller/notification_controller.dart';
import 'controller/user_controller.dart';
import 'package:show_talent/screens/main_screen.dart';
import 'package:show_talent/screens/splash_screen.dart';

// Handler pour les messages reçus en arrière-plan
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Message reçu en arrière-plan: ${message.messageId}');
}

// Plugin pour les notifications locales
FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// Canal de notification pour Android
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel', // ID unique
  'High Importance Notifications', // Nom visible
  description: 'Ce canal est utilisé pour les notifications importantes.',
  importance: Importance.max,
);

void initializeNotifications() async {
  // Initialisation des paramètres pour Android
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  // Initialiser Flutter Local Notifications
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Créer le canal pour Android
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

void requestPermission() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Demander la permission de recevoir des notifications
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print('Permission de notification accordée');
  } else {
    print('Permission de notification refusée');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisation de Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialisation des notifications et des permissions
  initializeNotifications();
  requestPermission();

  // Injection des contrôleurs dans GetX
  Get.put(AuthController());
  Get.put(OffreController());
  Get.put(NotificationController());
  Get.put(UserController());

  // Écoute des messages reçus lorsque l'application est au premier plan
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    // Afficher une notification locale si elle est reçue
    if (notification != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    }
  });

  // Écouter les messages reçus lorsque l'application est en arrière-plan ou complètement fermée
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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

        // Thème de l'AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF214D4F),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(
            color: Colors.white,
          ),
        ),

        // Thème pour les boutons (ElevatedButton)
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

        // Thème pour les champs de texte
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

        // Thème global du texte
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16, color: Color(0xFF214D4F)),
          bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF214D4F)),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF214D4F)),
          titleSmall: TextStyle(fontSize: 16, color: Color(0xFF214D4F)),
        ),
      ),
      home: const SplashScreen(),
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/main', page: () => const MainScreen()),
      ],
    );
  }
}
