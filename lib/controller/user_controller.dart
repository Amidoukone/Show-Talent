import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/login_screen.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/services/web_messaging_helper.dart';

/// UserController
/// - Gère le profil courant + la liste des users.
/// - Navigation fallback si AuthController absent.
class UserController extends GetxController {
  static UserController instance = Get.find();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Rx<AppUser?> _user = Rx<AppUser?>(null);
  AppUser? get user => _user.value;

  final Rx<List<AppUser>> _userList = Rx<List<AppUser>>([]);
  List<AppUser> get userList => _userList.value;

  bool _navigating = false;

  /// Fallback uniquement si AuthController n’est pas enregistré.
  bool get _shouldRouteHere => !Get.isRegistered<AuthController>();

  @override
  void onInit() {
    super.onInit();
    _bindAuthStream();
    _listenAllUsers();
  }

  void _bindAuthStream() {
    _auth.authStateChanges().listen(
      (User? firebaseUser) async {
        if (firebaseUser != null) {
          await _handleAuth(firebaseUser);
        } else {
          _user.value = null;
          if (_shouldRouteHere) {
            await _safeOffAll(const LoginScreen());
          }
        }
      },
      onError: (error) => debugPrint("Erreur auth stream : $error"),
    );
  }

  Future<void> _handleAuth(User firebaseUser) async {
    try {
      await firebaseUser.reload();
      final refreshed = _auth.currentUser;

      if (refreshed == null) {
        _user.value = null;
        if (_shouldRouteHere) {
          await _safeOffAll(const LoginScreen());
        }
        return;
      }

      final uid = refreshed.uid;

      // 1) Si email non vérifié → VerifyEmailScreen
      if (!refreshed.emailVerified) {
        try {
          final doc = await _firestore.collection('users').doc(uid).get();
          if (doc.exists) _user.value = AppUser.fromMap(doc.data()!);
        } catch (_) { /* no-op */ }

        if (_shouldRouteHere) {
          await _safeOffAll(const VerifyEmailScreen());
          _showSnackbar(
            'Email non vérifié',
            'Vérifiez votre e‑mail pour activer votre compte.',
            Colors.orange,
          );
        }
        return;
      }

      // 2) Email vérifié → synchronisation des métadonnées Firestore
      final doc = await _waitUserDoc(uid, attempts: 12, delay: const Duration(milliseconds: 250));
      if (doc == null || !doc.exists) {
        if (_shouldRouteHere) {
          await signOut();
        } else {
          debugPrint('UserController: profil utilisateur introuvable après attente.');
        }
        return;
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

      final updatedDoc = await _firestore.collection('users').doc(uid).get();
      _user.value = AppUser.fromMap(updatedDoc.data()!);

      // 3) Mise à jour du token FCM en silence
      await _updateFcmToken(uid);

      // 4) Navigation vers MainScreen si nécessaire
      if (_shouldRouteHere) {
        await _safeOffAll(const MainScreen());
      }
    } catch (e) {
      debugPrint("Erreur dans _handleAuth : $e");
      if (_shouldRouteHere) {
        await signOut();
      }
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

  Future<void> _listenAllUsers() async {
    _firestore.collection('users').snapshots().listen(
      (snapshot) {
        _userList.value = snapshot.docs
            .map((d) => AppUser.fromMap(d.data()))
            .where((u) => ((u.nom).trim().isNotEmpty))
            .toList();
        update();
      },
      onError: (e) => debugPrint("Erreur fetch users : $e"),
    );
  }

  Future<void> _updateFcmToken(String uid) async {
    try {
      final token = await WebMessagingHelper.getTokenWithRetry(retries: 2);
      if (token != null) {
        await _firestore.collection('users').doc(uid).set(
          {'fcmToken': token},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      debugPrint("Erreur update FCM token : $e");
    }
  }

  Future<void> refreshUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      _user.value = AppUser.fromMap(doc.data()!);
      update();
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      _user.value = null;

      if (_shouldRouteHere) {
        await _safeOffAll(const LoginScreen());
        _showSnackbar('Déconnexion', 'Vous êtes déconnecté', Colors.green);
      }
    } catch (e) {
      _showSnackbar('Erreur', 'Échec de déconnexion : $e', Colors.red);
    }
  }

  void _showSnackbar(String title, String message, Color color) {
    if (!_shouldRouteHere) return;
    Get.snackbar(
      title,
      message,
      backgroundColor: color,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _safeOffAll(Widget page) async {
    if (!_shouldRouteHere || _navigating) return;
    _navigating = true;
    try {
      await Get.offAll(() => page);
    } finally {
      _navigating = false;
    }
  }
}
