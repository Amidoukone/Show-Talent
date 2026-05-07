// lib/services/notifications.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

import 'users/user_repository.dart';
import 'web_messaging_helper.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Canal pour les notifications importantes',
    importance: Importance.max,
  );

  /// Init notifs locales (à appeler au démarrage)
  static Future<void> initLocal() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _local.initialize(initSettings);

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// Écoute les messages en premier plan (affiche une notif locale)
  static void listenForeground() {
    FirebaseMessaging.onMessage.listen((msg) {
      final notif = msg.notification;
      final android = notif?.android;
      if (notif != null && android != null) {
        _local.show(
          notif.hashCode,
          notif.title,
          notif.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });
  }

  /// Demande la permission (mobile & web) — à appeler après action utilisateur.
  /// Si accordée, récupère le token FCM et le stocke dans Firestore si user connecté.
  static Future<void> askPermissionAndUpdateToken({User? currentUser}) async {
    // 1) Demande de permission (mobile/web)
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2) Récupère un token robuste (VAPID sur Web)
    final token = await WebMessagingHelper.getTokenWithRetry(retries: 3);

    if (token == null) {
      debugPrint('NotificationService: aucun token FCM obtenu.');
      return;
    }

    // 3) Persiste en base si on a un user
    final user = currentUser ?? FirebaseAuth.instance.currentUser;
    if (user != null) {
      await UserRepository().saveFcmToken(user.uid, token);
    }
  }
}
