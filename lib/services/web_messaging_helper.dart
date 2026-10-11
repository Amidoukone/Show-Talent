// lib/services/web_messaging_helper.dart
import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';

/// Utilitaires Web/Mobile pour récupérer un token FCM de manière **silencieuse**.
/// Objectifs (surtout WEB) :
///  - Ne JAMAIS déclencher de prompt navigateur avant acceptation explicite.
///  - Ne demander un token que si l’autorisation est déjà accordée.
///  - Gérer un petit cache mémoire pour éviter les appels répétés.
class WebMessagingHelper {
  /// 🔑 Clé publique VAPID (Firebase Console ▸ Project settings ▸ Cloud Messaging ▸ Web configuration)
  /// C’est une clé **publique** embarquable côté client.
  static const String _vapidKey =
      String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');

  static String? _cachedToken;
  static DateTime? _cachedAt;

  /// Retourne le token FCM actuel.
  /// - **Web** : n’essaie **que** si la permission est déjà `authorized`
  ///             (sinon → null, aucun prompt).
  /// - **Mobile/Desktop** : appel direct.
  ///
  /// `retries` : essais courts pour laisser le SW se stabiliser.
  /// `forceRefresh` : ignore le cache en mémoire si `true`.
  static Future<String?> getTokenWithRetry({
    int retries = 3,
    bool forceRefresh = false,
  }) async {
    // ✅ Cache mémoire (30 min)
    if (!forceRefresh && _cachedToken != null) {
      final age = DateTime.now()
          .difference(_cachedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      if (age.inMinutes < 30) return _cachedToken;
    }

    if (!kIsWeb) {
      // Android / iOS / Desktop
      return _getMobileToken(retries: retries);
    }

    // 🌐 WEB
    // 1) Ne tente rien si FCM non supporté (navigateur / contexte)
    try {
      final supported = await FirebaseMessaging.instance.isSupported();
      if (supported != true) return null;
    } catch (_) {
      // Certaines versions ne fournissent pas isSupported(); on continue prudemment.
    }

    // 2) Lire l'état d'autorisation **sans** déclencher de prompt
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      final status = settings.authorizationStatus;
      // On n’essaie d’obtenir un token que si c’est déjà autorisé
      if (status != AuthorizationStatus.authorized) {
        return null; // silencieux : pas de prompt
      }
    } catch (_) {
      // Si l’API n’est pas dispo sur cette version, on préfère ne rien faire (silence)
      return null;
    }

    // 3) Essaie d’obtenir le token avec VAPID (permission déjà accordée)
    String? token;
    for (int attempt = 0; attempt <= retries && token == null; attempt++) {
      try {
        if (_vapidKey.isEmpty) {
          return null;
        }
        token = await FirebaseMessaging.instance.getToken(vapidKey: _vapidKey);
        _cachedToken = token;
        _cachedAt = DateTime.now();
        return token;
      } catch (_) {
        // ignore et retente
      }
      await Future.delayed(const Duration(milliseconds: 600));
    }

    return token; // peut être null si non disponible
  }

  /// Récupère le token FCM sur mobile, en attendant d'abord le jeton APNs.
  ///
  /// Sur iOS, `getToken()` ne peut pas répondre avant que le système ait
  /// livré le jeton APNs de l'appareil : il lève
  /// `[firebase_messaging/apns-token-not-set]`. Et ce jeton arrive de façon
  /// *asynchrone*, après l'accord de l'utilisateur — jamais à l'instant où
  /// `requestPermission()` rend la main, qui est précisément là où
  /// `NotificationService.askPermissionAndUpdateToken` le demandait.
  ///
  /// L'ancienne version attrapait cette exception et retournait `null` sans
  /// réessayer une seule fois (la boucle de réessai ne servait que le Web).
  /// Résultat : sur iOS aucun token n'était jamais enregistré, le backend
  /// répondait `token_missing` à chaque envoi, et personne ne recevait de
  /// notification — ni un message, ni la validation de sa propre vidéo. Rien
  /// ne le signalait côté utilisateur : l'écran venait de lui annoncer que
  /// les notifications étaient activées.
  static Future<String?> _getMobileToken({required int retries}) async {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await _awaitApnsToken();
    }

    // Le réessai couvre aussi Android : `getToken()` passe par le réseau
    // (enregistrement auprès de FCM) et échoue sur une connexion faible.
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          _cachedToken = token;
          _cachedAt = DateTime.now();
          return token;
        }
      } catch (_) {
        // Journalisé par l'appelant : NotificationService signale l'absence
        // de token, qui est la seule conséquence visible.
      }

      if (attempt < retries) {
        await Future<void>.delayed(_mobileRetryDelay * (attempt + 1));
      }
    }

    return null;
  }

  static const Duration _mobileRetryDelay = Duration(seconds: 2);

  /// Plafond d'attente du jeton APNs.
  ///
  /// Généreux : l'enregistrement auprès d'Apple est un aller-retour réseau,
  /// lent sur une connexion faible et au premier lancement. Dépasser ce délai
  /// n'abandonne pas — `getToken()` est tenté quand même, et ses réessais
  /// laissent une seconde chance au jeton d'arriver entre-temps.
  static const Duration _apnsTokenWait = Duration(seconds: 12);
  static const Duration _apnsPollInterval = Duration(milliseconds: 400);

  static Future<void> _awaitApnsToken() async {
    final deadline = DateTime.now().add(_apnsTokenWait);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns != null && apns.isNotEmpty) {
          return;
        }
      } catch (_) {
        // L'appel lui-même peut échouer avant que le plugin natif soit prêt ;
        // c'est une raison d'attendre, pas d'arrêter.
      }
      await Future<void>.delayed(_apnsPollInterval);
    }
  }
}
