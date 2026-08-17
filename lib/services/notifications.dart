// lib/services/notifications.dart
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_route.dart';
import 'users/user_repository.dart';
import 'web_messaging_helper.dart';
import 'package:adfoot/services/app_logger.dart';

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

  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _openedAppSub;

  static final StreamController<NotificationRoute> _routeTaps =
      StreamController<NotificationRoute>.broadcast();

  static NotificationRoute? _pendingRoute;

  /// Taps that happened while the app was already running.
  ///
  /// Broadcast so the UI can subscribe without the service ever reaching into
  /// navigation itself — keeping screen imports out of `lib/services`.
  static Stream<NotificationRoute> get routeTaps => _routeTaps.stream;

  /// Init notifs locales (à appeler au démarrage)
  static Future<void> initLocal() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await _local.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
    );

    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
  }

  /// Écoute les messages en premier plan (affiche une notif locale)
  static void listenForeground() {
    FirebaseMessaging.onMessage.listen((msg) {
      final notif = msg.notification;
      final android = notif?.android;
      if (notif != null && android != null) {
        _local.show(
          id: notif.hashCode,
          title: notif.title,
          body: notif.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              icon: '@mipmap/ic_launcher',
            ),
          ),
          // Without this the locally re-rendered notification is a dead end:
          // FCM's own `data` never reaches the tap handler, so a notification
          // that arrives while the app is open — the common case for a
          // moderation decision the author is waiting on — could not be
          // routed anywhere.
          payload: _encodePayload(msg.data),
        );
      }
    });
  }

  /// Routes taps on notifications delivered by the system (app backgrounded or
  /// killed), and replays the one that launched the app.
  ///
  /// Called during bootstrap, i.e. before `runApp`, so a cold-start tap cannot
  /// navigate yet. It is parked in [_pendingRoute] and handed to the UI by
  /// [takePendingRoute] once a screen exists to navigate from.
  static Future<void> listenNotificationTaps() async {
    await _openedAppSub?.cancel();
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(
      (msg) => _dispatch(resolveNotificationRoute(msg.data)),
      onError: (Object error) {
        AppLogger.debug('NotificationService onMessageOpenedApp error: $error');
      },
    );

    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _dispatch(resolveNotificationRoute(initial.data));
      }
    } catch (error) {
      AppLogger.debug('NotificationService getInitialMessage error: $error');
    }
  }

  /// Keeps the token stored server-side in step with the one FCM is actually
  /// using.
  ///
  /// FCM rotates registration tokens on its own — after a restore onto a new
  /// phone, a "clear data", a reinstall, or long inactivity. Persisting only
  /// at sign-in (AuthController._updateFcmToken) leaves the backend holding a
  /// token that is already dead, and every later notification is dropped by
  /// FCM without a single visible error: the author of an approved video
  /// simply never hears about it. This is the only signal we get that the
  /// token changed.
  static Future<void> listenTokenRefresh() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          // Signed out: nowhere to attach the token. The next sign-in
          // re-reads and persists whatever the current token is.
          return;
        }
        try {
          await UserRepository().saveFcmToken(user.uid, token);
        } catch (error) {
          AppLogger.debug('NotificationService token refresh save: $error');
        }
      },
      onError: (Object error) {
        AppLogger.debug('NotificationService onTokenRefresh error: $error');
      },
    );
  }

  /// Consumes the route captured before any screen was mounted, if any.
  ///
  /// Single-shot on purpose: a cold-start tap must open its destination once,
  /// not again on every rebuild or every return to the shell.
  static NotificationRoute? takePendingRoute() {
    final route = _pendingRoute;
    _pendingRoute = null;
    return route;
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
      AppLogger.debug('NotificationService: aucun token FCM obtenu.');
      return;
    }

    // 3) Persiste en base si on a un user
    final user = currentUser ?? FirebaseAuth.instance.currentUser;
    if (user != null) {
      await UserRepository().saveFcmToken(user.uid, token);
    }
  }

  static String? _encodePayload(Map<String, dynamic> data) {
    if (data.isEmpty) return null;
    try {
      return jsonEncode(
        data.map((key, value) => MapEntry(key, value?.toString())),
      );
    } catch (error) {
      AppLogger.debug('NotificationService payload encode error: $error');
      return null;
    }
  }

  static void _handleLocalNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _dispatch(
          resolveNotificationRoute(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    } catch (error) {
      AppLogger.debug('NotificationService payload decode error: $error');
    }
  }

  static void _dispatch(NotificationRoute route) {
    if (!route.isActionable) return;

    if (_routeTaps.hasListener) {
      _routeTaps.add(route);
      return;
    }

    // No screen is listening yet (cold start, or the shell is being rebuilt).
    // Hold the route rather than dropping it.
    _pendingRoute = route;
  }
}
