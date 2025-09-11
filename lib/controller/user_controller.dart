import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/login_screen.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// UserController
/// - Source de vérité pour la navigation (Login / Verify / Main)
/// - Hydrate AppUser, écoute FirebaseAuth et Firestore.
/// - Navigation SAFE: n'exécute pas Get.offAll tant que le Navigator n'est pas prêt.
/// - Si le doc Firestore n'existe pas encore, il est créé idempotemment.
class UserController extends GetxController {
  static UserController instance = Get.find();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Rx<AppUser?> _user = Rx<AppUser?>(null);
  AppUser? get user => _user.value;

  final Rx<List<AppUser>> _userList = Rx<List<AppUser>>([]);
  List<AppUser> get userList => _userList.value;

  bool _navigating = false;
  bool _navScheduled = false; // empêche les doublons pendant l'init

  @override
  void onInit() {
    super.onInit();

    // 🔁 idTokenChanges => login/logout/refresh
    _auth.idTokenChanges().listen(
      (User? firebaseUser) async {
        await _routeFromAuth(firebaseUser);
      },
      onError: (e) => debugPrint('UserController idTokenChanges error: $e'),
    );

    _listenAllUsers();

    // Réveil après 1er frame (cold start)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      kickstart();
    });
  }

  /// Permet de relancer une passe de routage (appelé par Splash/Login si besoin)
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

      // 1) Email non vérifié → hydrate min. et route Verify
      if (!refreshed.emailVerified) {
        try {
          final doc = await _firestore.collection('users').doc(uid).get();
          if (doc.exists) _user.value = AppUser.fromMap(doc.data()!);
        } catch (_) {/* no-op */}
        await _safeOffAll(const VerifyEmailScreen());
        return;
      }

      // 2) Email vérifié → s'assurer que le doc Firestore est prêt
      var doc = await _waitUserDoc(uid, attempts: 20, delay: const Duration(milliseconds: 250));
      if (doc == null || !doc.exists) {
        // 🔧 Création idempotente du profil minimal si nécessaire
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'email': refreshed.email,
          'nom': refreshed.displayName ?? '',
          'photoUrl': refreshed.photoURL,
          'createdAt': FieldValue.serverTimestamp(),
          'estActif': true,
          'emailVerified': true,
          'emailVerifiedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Relire le doc
        doc = await _firestore.collection('users').doc(uid).get();
        if (!doc.exists) {
          // Si toujours pas dispo (réseau très lent), ne casse pas le login :
          // route vers Main et l'hydratation finira en arrière-plan.
          await _safeOffAll(const MainScreen());
          return;
        }
      }

      // 3) Hydrate AppUser
      final userData = AppUser.fromMap(doc.data()!);
      _user.value = userData;

      // 4) Route vers Main uniquement quand AppUser est prêt
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
      // Navigation: idTokenChanges -> _routeFromAuth
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

  // --- Navigation robuste / idempotente / navigator-aware ---
  Future<void> _safeOffAll(Widget page) async {
    // Navigator pas prêt ? on postpose au prochain frame
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
      // Évite de boucler si on est déjà sur la bonne page
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
    // VerifyEmailScreen: pas de route nommée dédiée (différente de /verify web)
    return null;
  }
}
