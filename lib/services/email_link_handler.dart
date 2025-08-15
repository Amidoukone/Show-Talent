// lib/screens/email_link_handler.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Gère les liens de vérification Firebase (mode=verifyEmail & oobCode=...)
/// via App/Universal Links (package:app_links) — sans Firebase Dynamic Links.
class EmailLinkHandler {
  static StreamSubscription<Uri?>? _sub;
  static AppLinks? _appLinks;

  // Empêche ré-initialisations accidentelles
  static bool _initialized = false;

  // Anti double-traitement (ex: même lien reçu plusieurs fois)
  static final Set<String> _handledOobCodes = <String>{};

  /// Hôtes autorisés pour les liens de vérification.
  /// - adfoot.org (Custom action URL)
  /// - show-talent-5987d.web.app & .firebaseapp.com (liens Firebase natifs)
  static const Set<String> _allowedHosts = {
    'adfoot.org',
    'show-talent-5987d.web.app',
    'show-talent-5987d.firebaseapp.com',
  };

  /// Initialise l'écoute des liens d'application (cold + warm).
  static Future<void> init() async {
    // app_links n’est pas pour le Web
    if (kIsWeb) return;
    if (_initialized) return;
    _initialized = true;

    try {
      _appLinks ??= AppLinks(); // singleton

      // Cold start — lien ayant lancé l’app
      try {
        final initialUri = await _appLinks!
            .getInitialLink()
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (initialUri != null) {
          await _handle(initialUri);
        }
      } on PlatformException catch (e) {
        if (kDebugMode) {
          print("app_links getInitialLink PlatformException: $e");
        }
      } catch (e) {
        if (kDebugMode) {
          print("app_links getInitialLink unexpected: $e");
        }
      }

      // Warm/Hot links — liens reçus quand l’app est déjà ouverte
      await _sub?.cancel();
      _sub = _appLinks!.uriLinkStream.listen(
        (Uri? uri) {
          if (uri != null) {
            // ignore: discarded_futures
            _handle(uri);
          }
        },
        onError: (e) {
          if (kDebugMode) print("app_links stream error: $e");
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (kDebugMode) print("app_links init failed: $e");
    }
  }

  /// Traite un lien entrant. Retourne true si un traitement a été effectué.
  static Future<bool> _handle(Uri link) async {
    // Filtre de sécurité: HTTPS + hôte autorisé
    if (link.scheme != 'https' || !_allowedHosts.contains(link.host)) {
      if (kDebugMode) {
        print('EmailLinkHandler: lien ignoré (host non autorisé): $link');
      }
      return false;
    }

    // Firebase ajoute ces paramètres
    final mode = link.queryParameters['mode'];
    final oob = link.queryParameters['oobCode'];

    // On ne traite que la vérification d’e-mail
    if (mode != 'verifyEmail' || oob == null || oob.isEmpty) {
      if (kDebugMode) {
        print('EmailLinkHandler: lien non pertinent (mode/oobCode manquant): $link');
      }
      return false;
    }

    // Anti double-traitement
    if (_handledOobCodes.contains(oob)) {
      if (kDebugMode) {
        print('EmailLinkHandler: oobCode déjà traité, on ignore.');
      }
      return false;
    }
    _handledOobCodes.add(oob);

    try {
      // Valide et applique le code d’action
      await FirebaseAuth.instance.checkActionCode(oob);
      await FirebaseAuth.instance.applyActionCode(oob);

      // Recharge l’utilisateur (emailVerified doit passer à true)
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        // Mise à jour Firestore idempotente
        final userRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);
        final snap = await userRef.get();

        final updates = <String, dynamic>{
          'emailVerified': true,
          'estActif': true,
          'emailVerifiedAt': FieldValue.serverTimestamp(),
          'dernierLogin': DateTime.now(),
        };

        if (snap.exists) {
          await userRef.set(updates, SetOptions(merge: true));
        } else {
          await userRef.set(updates, SetOptions(merge: true));
        }

        if (kDebugMode) {
          print('EmailLinkHandler: Vérification appliquée et Firestore mis à jour.');
        }
      } else {
        if (kDebugMode) {
          print('EmailLinkHandler: Aucun utilisateur connecté après applyActionCode.');
        }
      }

      return true;
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print("EmailLinkHandler applyActionCode FirebaseAuthException: ${e.code} ${e.message}");
      }
      return false;
    } catch (e) {
      if (kDebugMode) print("EmailLinkHandler applyActionCode unexpected: $e");
      return false;
    }
  }

  /// Libère les ressources (utile si tu veux stopper l’écoute au logout, etc.)
  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _appLinks = null;
    _initialized = false;
    _handledOobCodes.clear();
  }
}
