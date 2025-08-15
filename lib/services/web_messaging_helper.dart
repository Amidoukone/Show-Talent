// lib/services/web_messaging_helper.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
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
      'BLngrlSTZrTe-mexPQOdiYul_qFP1bRZnrv7UCHwVA9vXkuYUJ1oJ3tUnD5B5QDyk6d1eSVRFG18ECIEBAazUho';

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
      final age = DateTime.now().difference(_cachedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      if (age.inMinutes < 30) return _cachedToken;
    }

    if (!kIsWeb) {
      // Android / iOS / Desktop
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          _cachedToken = token;
          _cachedAt = DateTime.now();
        }
        return token;
      } catch (_) {
        return null;
      }
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
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final status = settings.authorizationStatus;
      // On n'essaie d'obtenir un token que si c'est déjà autorisé
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
}
