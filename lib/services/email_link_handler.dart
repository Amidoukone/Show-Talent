// lib/services/email_link_handler.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';

/// Gère les liens de vérification Firebase (mode=verifyEmail & oobCode=...)
/// via App/Universal Links (package:app_links) — pas de Firebase Dynamic Links.
/// - Mobile: écoute des liens d'app.
/// - Web: no-op (géré dans VerifyEmailScreen).
class EmailLinkHandler {
  static AppLinks? _appLinks;
  static StreamSubscription<Uri?>? _sub;

  // Empêche les ré-initialisations multiples.
  static bool _initialized = false;

  // Anti double-traitement (ex: même lien reçu plusieurs fois).
  static final Set<String> _handledOobCodes = <String>{};

  // Flux "email vérifié" pour notifier l'UI (VerifyEmailScreen).
  static StreamController<void>? _verifiedCtrl;
  static Stream<void> get onEmailVerified {
    _verifiedCtrl ??= StreamController<void>.broadcast();
    return _verifiedCtrl!.stream;
  }

  static void _emitVerified() {
    try {
      _verifiedCtrl?.add(null);
    } catch (_) {}
  }

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
    if (kIsWeb) return; // sur Web, géré directement par VerifyEmailScreen
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
          print("EmailLinkHandler.getInitialLink PlatformException: $e");
        }
      } catch (e) {
        if (kDebugMode) {
          print("EmailLinkHandler.getInitialLink unexpected: $e");
        }
      }

      // Warm/Hot links — quand l’app est déjà ouverte
      await _sub?.cancel();
      _sub = _appLinks!.uriLinkStream.listen(
        (Uri? uri) {
          if (uri != null) {
            // ignore: discarded_futures
            _handle(uri);
          }
        },
        onError: (e) {
          if (kDebugMode) print("EmailLinkHandler stream error: $e");
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (kDebugMode) print("EmailLinkHandler.init failed: $e");
    }
  }

  static Map<String, String> _mergedParamsFrom(Uri uri) {
    final params = <String, String>{...uri.queryParameters};
    if (uri.fragment.isNotEmpty) {
      try {
        params.addAll(Uri.splitQueryString(uri.fragment));
      } catch (_) {}
    }
    return params;
  }

  /// Traite un lien entrant. Retourne true si un traitement a été effectué.
  static Future<bool> _handle(Uri link) async {
    // Sécurité: HTTPS + hôte autorisé
    if (link.scheme != 'https' || !_allowedHosts.contains(link.host)) {
      if (kDebugMode) {
        print('EmailLinkHandler: lien ignoré (host non autorisé): $link');
      }
      return false;
    }

    final params = _mergedParamsFrom(link);
    final mode = params['mode'];
    final oob = params['oobCode'];

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
      await FirebaseAuth.instance.checkActionCode(oob);
      await FirebaseAuth.instance.applyActionCode(oob);

      // Recharge l’utilisateur (emailVerified doit passer à true s'il est connecté)
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        // Mise à jour Firestore idempotente
        final userRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);
        await userRef.set({
          'emailVerified': true,
          'estActif': true,
          'emailVerifiedAt': FieldValue.serverTimestamp(),
          'dernierLogin': DateTime.now(),
        }, SetOptions(merge: true));
      }

      // Notifie l'UI (VerifyEmailScreen) qu'une vérification a eu lieu
      _emitVerified();
      if (kDebugMode) {
        print('EmailLinkHandler: Vérification appliquée et Firestore mis à jour.');
      }
      return true;
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print("EmailLinkHandler FirebaseAuthException: ${e.code} ${e.message}");
      }
      return false;
    } catch (e) {
      if (kDebugMode) print("EmailLinkHandler unexpected: $e");
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
    await _verifiedCtrl?.close();
    _verifiedCtrl = null;
  }
}
