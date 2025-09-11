import 'package:adfoot/models/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/services/notifications.dart';
import 'package:adfoot/services/web_messaging_helper.dart';

/// AuthController ne navigue plus.
/// - Il maintient AppUser "métier", synchronise Firestore,
///   gère FCM et permission système.
/// - La navigation est entièrement gérée par UserController.
class AuthController extends GetxController {
  static AuthController instance = Get.find();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Rx<User?> _firebaseUser = Rx<User?>(null);
  final Rx<AppUser?> _appUser = Rx<AppUser?>(null);

  AppUser? get user => _appUser.value;
  String? get currentUid => _appUser.value?.uid;

  bool _askedNotifThisSession = false;

  @override
  void onReady() {
    super.onReady();
    // On continue d’écouter pour garder _appUser à jour,
    // mais on NE NAVIGUE PAS.
    _firebaseUser.bindStream(_auth.idTokenChanges());
    ever<User?>(_firebaseUser, _syncState);
    // Cold start
    _syncState(_auth.currentUser);
  }

  /// Met à jour _appUser et Firestore (si nécessaire).
  /// Pas de navigation ici.
  Future<void> _syncState(User? firebaseUser) async {
    if (firebaseUser == null) {
      _appUser.value = null;
      return;
    }

    try {
      await firebaseUser.reload();
      final refreshed = _auth.currentUser;
      if (refreshed == null) {
        _appUser.value = null;
        return;
      }

      final uid = refreshed.uid;

      // Email non vérifié : on hydrate si doc existe, sans router.
      if (!refreshed.emailVerified) {
        try {
          final doc = await _firestore.collection('users').doc(uid).get();
          _appUser.value = doc.exists ? AppUser.fromMap(doc.data()!) : null;
        } catch (_) {
          _appUser.value = null;
        }
        return;
      }

      // Email vérifié : on s’assure que le doc existe
      final doc = await _waitUserDoc(uid, attempts: 20, delay: const Duration(milliseconds: 250));
      if (doc == null || !doc.exists) {
        _appUser.value = null;
        return;
      }

      final userData = AppUser.fromMap(doc.data()!);

      // Sync idempotente
      final updates = <String, dynamic>{};
      if (userData.emailVerified != true) updates['emailVerified'] = true;
      if (userData.estActif != true) updates['estActif'] = true;
      if (userData.emailVerifiedAt == null) {
        updates['emailVerifiedAt'] = FieldValue.serverTimestamp();
      }
      if (updates.isNotEmpty) {
        await _firestore.collection('users').doc(uid).update(updates);
      }

      final updated = await _firestore.collection('users').doc(uid).get();
      _appUser.value = AppUser.fromMap(updated.data()!);

      // Mise à jour FCM si dispo
      await _updateFcmToken(refreshed);

      // Demande permission système (une fois par session)
      await _ensureSystemNotificationPromptOnce(refreshed);
    } catch (e) {
      debugPrint('AuthController _syncState error: $e');
      _appUser.value = null;
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _waitUserDoc(
    String uid, {
    int attempts = 6,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    DocumentSnapshot<Map<String, dynamic>>? doc;
    for (int i = 0; i < attempts; i++) {
      doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) return doc;
      await Future.delayed(delay);
    }
    return doc;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _appUser.value = null;
    // Pas de navigation ici; UserController réagira au sign-out et routera.
  }

  Future<void> _updateFcmToken(User user) async {
    try {
      final token = await WebMessagingHelper.getTokenWithRetry(retries: 2);
      if (token != null) {
        await _firestore.collection('users').doc(user.uid).set(
          {'fcmToken': token},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      debugPrint('AuthController _updateFcmToken error: $e');
    }
  }

  Future<void> _ensureSystemNotificationPromptOnce(User user) async {
    if (_askedNotifThisSession) return;
    _askedNotifThisSession = true;
    try {
      await NotificationService.askPermissionAndUpdateToken(currentUser: user);
    } catch (e) {
      debugPrint('AuthController notifications permission error: $e');
    }
  }

  /// Appelée par tes écrans (Login/Verify) – garde le même nom/signature
  /// pour compatibilité. Elle ne navigue pas, elle synchronise juste l’état.
  Future<void> handleAuthState(User? firebaseUser) => _syncState(firebaseUser);
}
