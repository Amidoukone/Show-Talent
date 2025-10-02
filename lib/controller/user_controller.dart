// lib/controller/user_controller.dart

import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/login_screen.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// UserController
/// - Source de vérité pour l’état utilisateur, navigation (Login / Verify / Main)
/// - Hydrate AppUser, écoute FirebaseAuth et Firestore.
/// - Ne perd pas les fonctionnalités existantes, tout en ajoutant robustesse.
class UserController extends GetxController {
  static UserController instance = Get.find();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Rx<AppUser?> _user = Rx<AppUser?>(null);
  AppUser? get user => _user.value;

  final Rx<List<AppUser>> _userList = Rx<List<AppUser>>([]);
  List<AppUser> get userList => _userList.value;

  bool _navigating = false;
  bool _navScheduled = false;

  @override
  void onInit() {
    super.onInit();

    // écoute les changements d’auth (login / logout / refresh)
    _auth.idTokenChanges().listen(
      (User? firebaseUser) async {
        await _routeFromAuth(firebaseUser);
      },
      onError: (e) => debugPrint('UserController idTokenChanges error: $e'),
    );

    _listenAllUsers();

    // Le trigger initial après le premier frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      kickstart();
    });
  }

  /// Lance le routage selon l’état utilisateur actuel
  void kickstart() {
    _routeFromAuth(_auth.currentUser);
  }

  Future<void> _routeFromAuth(User? firebaseUser) async {
    try {
      if (firebaseUser == null) {
        _user.value = null;
        await _safeOffAll(const LoginScreen());
        return;
      }

      await firebaseUser.reload();
      final refreshed = _auth.currentUser;
      if (refreshed == null) {
        _user.value = null;
        await _safeOffAll(const LoginScreen());
        return;
      }

      final uid = refreshed.uid;

      // Cas : email non vérifié → accéder à vérification
      if (!refreshed.emailVerified) {
        try {
          final doc = await _firestore.collection('users').doc(uid).get();
          if (doc.exists) {
            _user.value = AppUser.fromMap(doc.data()!);
          }
        } catch (_) {
          // ignore
        }
        await _safeOffAll(const VerifyEmailScreen());
        return;
      }

      // Cas : email vérifié → s’assurer que document utilisateur existe
      var doc = await _waitUserDoc(uid, attempts: 20, delay: const Duration(milliseconds: 250));
      if (doc == null || !doc.exists) {
        // création minimale du profil si absent
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'email': refreshed.email,
          'nom': refreshed.displayName ?? '',
          'photoProfil': refreshed.photoURL ?? '',
          'dateInscription': FieldValue.serverTimestamp(),
          'estActif': true,
          'emailVerified': true,
          'emailVerifiedAt': FieldValue.serverTimestamp(),
          // initialiser les listes vides pour éviter null
          'followersList': <String>[],
          'followingsList': <String>[],
        }, SetOptions(merge: true));

        doc = await _firestore.collection('users').doc(uid).get();
        if (!doc.exists) {
          await _safeOffAll(const MainScreen());
          return;
        }
      }

      final userData = AppUser.fromMap(doc.data()!);
      _user.value = userData;

      await _safeOffAll(const MainScreen());
    } catch (e) {
      debugPrint('UserController _routeFromAuth error: $e');
      _user.value = null;
      await _safeOffAll(const LoginScreen());
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _waitUserDoc(
    String uid, {
    int attempts = 20,
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
            .where((u) => (u.nom).trim().isNotEmpty)
            .toList();
        update();
      },
      onError: (e) => debugPrint("Erreur fetch users : $e"),
    );
  }

  /// Rafraîchit les données de l’utilisateur connecté depuis Firestore
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
      // idTokenChanges déclenchera la redirection vers Login
    } catch (e) {
      Get.snackbar(
        'Erreur',
        'Échec de déconnexion : $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _safeOffAll(Widget page) async {
    if (Get.key.currentState == null) {
      if (_navScheduled) return;
      _navScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _navScheduled = false;
        await _safeOffAll(page);
      });
      return;
    }

    if (_navigating) return;
    _navigating = true;
    try {
      final String current = Get.currentRoute;
      final String? target = _namedRouteFor(page);
      if (target != null && current == target) return;

      await Get.offAll(() => page);
    } finally {
      _navigating = false;
    }
  }

  String? _namedRouteFor(Widget page) {
    if (page is LoginScreen) return '/login';
    if (page is MainScreen) return '/main';
    if (page is VerifyEmailScreen) return '/verify';
    return null;
  }
}
