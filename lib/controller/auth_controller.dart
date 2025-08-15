import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/login_screen.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/services/notifications.dart';
import 'package:adfoot/services/web_messaging_helper.dart';

class AuthController extends GetxController {
  static AuthController instance = Get.find();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Rx<User?> _firebaseUser = Rx<User?>(null);
  final Rx<AppUser?> _appUser = Rx<AppUser?>(null);

  AppUser? get user => _appUser.value;
  String? get currentUid => _appUser.value?.uid;

  bool _navigating = false;
  bool _askedNotifThisSession = false;

  @override
  void onReady() {
    super.onReady();
    _firebaseUser.bindStream(_auth.authStateChanges());
    ever<User?>(_firebaseUser, handleAuthState);
    handleAuthState(_auth.currentUser); // Cold-start
  }

  Future<void> handleAuthState(User? firebaseUser) async {
    if (firebaseUser == null) {
      _appUser.value = null;
      return _safeOffAll(const LoginScreen());
    }

    try {
      await firebaseUser.reload();
      final refreshed = _auth.currentUser;
      if (refreshed == null) {
        _appUser.value = null;
        return _safeOffAll(const LoginScreen());
      }

      final uid = refreshed.uid;

      // 📩 Priorité à la vérification email
      if (!refreshed.emailVerified) {
        try {
          final doc = await _firestore.collection('users').doc(uid).get();
          _appUser.value = doc.exists ? AppUser.fromMap(doc.data()!) : null;
        } catch (_) {
          _appUser.value = null;
        }
        return _safeOffAll(const VerifyEmailScreen());
      }

      // ✅ Email vérifié
      final doc = await _waitUserDoc(uid, attempts: 20, delay: const Duration(milliseconds: 250));
      if (doc == null || !doc.exists) {
        _appUser.value = null;
        return _safeOffAll(const LoginScreen());
      }

      final userData = AppUser.fromMap(doc.data()!);

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

      await _updateFcmToken(refreshed);
      await _safeOffAll(const MainScreen());
      await _maybeAskNotifications(refreshed);

    } catch (e) {
      debugPrint('AuthController.handleAuthState error: $e');
      _appUser.value = null;
      return _safeOffAll(const LoginScreen());
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
    return _safeOffAll(const LoginScreen());
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

  Future<void> _maybeAskNotifications(User user) async {
    if (_askedNotifThisSession) return;
    _askedNotifThisSession = true;

    await Future.delayed(const Duration(milliseconds: 300));
    if (Get.isDialogOpen == true) return;

    final accepted = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Activer les notifications ?'),
        content: const Text(
          "Recevez une alerte quand un recruteur consulte vos vidéos, "
          "quand vous recevez un message, ou qu’une nouvelle offre vous concerne.",
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Plus tard'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Activer'),
          ),
        ],
      ),
      barrierDismissible: true,
    );

    if (accepted == true) {
      await NotificationService.askPermissionAndUpdateToken(currentUser: user);
      Get.snackbar(
        'Notifications',
        'Activées (si autorisées par le navigateur).',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _safeOffAll(Widget page) async {
    if (_navigating) return;
    _navigating = true;
    try {
      await Get.offAll(() => page);
    } finally {
      _navigating = false;
    }
  }
}
