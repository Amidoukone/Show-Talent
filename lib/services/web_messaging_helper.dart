// lib/services/web_messaging_helper.dart
import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:adfoot/services/app_logger.dart';

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
    final isApplePlatform =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    var apnsArrived = true;
    if (isApplePlatform) {
      apnsArrived = await _awaitApnsToken();
    }

    // Le réessai couvre aussi Android : `getToken()` passe par le réseau
    // (enregistrement auprès de FCM) et échoue sur une connexion faible.
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          _cachedToken = token;
          _cachedAt = DateTime.now();
          return token;
        }
        lastError ??= 'getToken() returned null';
      } catch (error) {
        lastError = error;
      }

      if (attempt < retries) {
        await Future<void>.delayed(_mobileRetryDelay * (attempt + 1));
      }
    }

    // Dire *laquelle* des deux étapes a échoué, parce qu'elles ne se
    // réparent pas au même endroit.
    //
    // « aucun jeton » couvrait deux pannes distinctes : le système n'a jamais
    // livré le jeton APNs de l'appareil (enregistrement auprès d'Apple :
    // capability de l'App ID, profil, entitlement, réseau), ou il l'a livré
    // et c'est l'enregistrement auprès de FCM qui échoue (projet, réseau,
    // configuration Firebase). Sans cette distinction, la cause se cherche
    // par élimination à chaque build — ce qui a déjà coûté deux tours.
    //
    // `error`, pas `warning` : les warnings sont échantillonnés à 15 % en
    // production, et c'est une capacité perdue, pas du bruit.
    if (isApplePlatform && !apnsArrived) {
      AppLogger.error(
        'the system never delivered an APNs device token within '
        '${_apnsTokenWait.inSeconds}s; FCM cannot issue a registration token '
        'without it, so nothing can be delivered to this device',
        source: 'notifications/apns_token_absent',
      );
    } else {
      AppLogger.error(
        'an APNs device token exists but FCM refused to issue a registration '
        'token after ${retries + 1} attempts: $lastError',
        source: 'notifications/fcm_registration_failed',
      );
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
  ///
  /// Porté de 12 s à 30 s : un appareil réel a signalé
  /// `AuthorizationStatus.authorized` sans jamais produire de jeton dans les
  /// 12 s, et il n'existe aucune seconde chance plus tard dans la session —
  /// `onTokenRefresh` ne se déclenche que lorsqu'un jeton est *généré*, donc
  /// une génération qui échoue à chaque fois ne notifie jamais rien. Attendre
  /// ne coûte rien : tout ceci tourne hors du chemin de connexion.
  static const Duration _apnsTokenWait = Duration(seconds: 30);
  static const Duration _apnsPollInterval = Duration(milliseconds: 400);

  /// `true` dès que le système a livré le jeton APNs de l'appareil.
  static Future<bool> _awaitApnsToken() async {
    final deadline = DateTime.now().add(_apnsTokenWait);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns != null && apns.isNotEmpty) {
          return true;
        }
      } catch (_) {
        // L'appel lui-même peut échouer avant que le plugin natif soit prêt ;
        // c'est une raison d'attendre, pas d'arrêter.
      }
      await Future<void>.delayed(_apnsPollInterval);
    }

    return false;
  }
}
