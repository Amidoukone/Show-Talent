import 'dart:async';

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
/// - Hydrate AppUser
/// - Écoute FirebaseAuth + Firestore
/// - 🔥 Ajoute un cache réactif par UID pour les vidéos
class UserController extends GetxController {
  static UserController instance = Get.find();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ---------------------------------------------------------------------------
  /// UTILISATEUR CONNECTÉ
  /// ---------------------------------------------------------------------------

  final Rx<AppUser?> _user = Rx<AppUser?>(null);
  AppUser? get user => _user.value;

  /// ---------------------------------------------------------------------------
  /// LISTE USERS (fonctionnalité existante conservée)
  /// ---------------------------------------------------------------------------

  final Rx<List<AppUser>> _userList = Rx<List<AppUser>>([]);
  List<AppUser> get userList => _userList.value;

  /// ---------------------------------------------------------------------------
  /// 🔥 CACHE GLOBAL RÉACTIF PAR UID (NOUVEAU)
  /// ---------------------------------------------------------------------------

  final RxMap<String, AppUser> usersCache = <String, AppUser>{}.obs;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;

  bool _navigating = false;
  bool _navScheduled = false;

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();

    /// Auth listener
    _auth.idTokenChanges().listen(
      (User? firebaseUser) async {
        await _routeFromAuth(firebaseUser);
      },
      onError: (e) => debugPrint('UserController idTokenChanges error: $e'),
    );

    /// 🔥 Écoute globale des users (1 seule fois)
    _listenAllUsers();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      kickstart();
    });
  }

  /// Lance le routage selon l’état utilisateur actuel
  void kickstart() {
    _routeFromAuth(_auth.currentUser);
  }

  // ---------------------------------------------------------------------------
  // ROUTING AUTH
  // ---------------------------------------------------------------------------

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

      /// Email non vérifié
      if (!refreshed.emailVerified) {
        try {
          final doc = await _firestore.collection('users').doc(uid).get();
          if (doc.exists) {
            final u = AppUser.fromMap(doc.data()!);
            _user.value = u;
            usersCache[u.uid] = u;
          }
        } catch (_) {}
        await _safeOffAll(const VerifyEmailScreen());
        return;
      }

      /// S’assurer que le document utilisateur existe
      var doc = await _waitUserDoc(
        uid,
        attempts: 20,
        delay: const Duration(milliseconds: 250),
      );

      if (doc == null || !doc.exists) {
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'email': refreshed.email,
          'nom': refreshed.displayName ?? '',
          'photoProfil': refreshed.photoURL ?? '',
          'dateInscription': FieldValue.serverTimestamp(),
          'estActif': true,
          'emailVerified': true,
          'emailVerifiedAt': FieldValue.serverTimestamp(),
          'followersList': <String>[],
          'followingsList': <String>[],
        }, SetOptions(merge: true));

        doc = await _firestore.collection('users').doc(uid).get();
      }

      if (!doc.exists) {
        await _safeOffAll(const MainScreen());
        return;
      }

      final userData = AppUser.fromMap(doc.data()!);
      _user.value = userData;
      usersCache[userData.uid] = userData;

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

  // ---------------------------------------------------------------------------
  // 🔥 LISTENER USERS GLOBAL (CACHE + userList)
  // ---------------------------------------------------------------------------

  Future<void> _listenAllUsers() async {
    _usersSub?.cancel();
    _usersSub = _firestore.collection('users').snapshots().listen(
      (snapshot) {
        final List<AppUser> list = [];

        for (final d in snapshot.docs) {
          final user = AppUser.fromMap(d.data());

          /// cache global par uid
          usersCache[user.uid] = user;

          /// user connecté
          if (_user.value?.uid == user.uid) {
            _user.value = user;
          }

          if (user.nom.trim().isNotEmpty) {
            list.add(user);
          }
        }

        _userList.value = list;
        update(); // compatibilité écrans existants
      },
      onError: (e) => debugPrint("Erreur fetch users : $e"),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔥 ACCÈS USER PAR UID (VIDÉOS)
  // ---------------------------------------------------------------------------

  AppUser? getUserById(String uid) {
    return usersCache[uid];
  }

  // ---------------------------------------------------------------------------
  // REFRESH / SIGNOUT
  // ---------------------------------------------------------------------------

  Future<void> refreshUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      final u = AppUser.fromMap(doc.data()!);
      _user.value = u;
      usersCache[u.uid] = u;
      update();
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      _user.value = null;
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

  // ---------------------------------------------------------------------------
  // SAFE NAV
  // ---------------------------------------------------------------------------

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

  @override
  void onClose() {
    _usersSub?.cancel();
    super.onClose();
  }
}