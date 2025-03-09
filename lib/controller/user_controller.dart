import 'package:adfoot/screens/login_screen.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/user.dart';

class UserController extends GetxController {
  static UserController instance = Get.find();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final Rx<AppUser?> _user = Rx<AppUser?>(null);
  AppUser? get user => _user.value;

  final Rx<List<AppUser>> _userList = Rx<List<AppUser>>([]);
  List<AppUser> get userList => _userList.value;

  @override
  void onInit() {
    super.onInit();
    _bindUserStream();
    _fetchAllUsers();
  }

  /// Écoute les changements d'état de l'utilisateur Firebase**
  void _bindUserStream() {
    _auth.authStateChanges().listen((User? firebaseUser) async {
      if (firebaseUser != null) {
        await handleUserState(firebaseUser.uid);
      } else {
        _user.value = null;
        Get.offAll(() => const LoginScreen());
      }
    }, onError: (error) {
      debugPrint("Erreur flux auth : $error");
    });
  }

  /// Met à jour l'utilisateur depuis Firestore
  Future<void> refreshUserData() async {
    final User? firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return;

    final userDoc = await _firestore.collection('users').doc(firebaseUser.uid).get();
    if (userDoc.exists) {
      _user.value = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
      update(); //  Met à jour immédiatement l'interface utilisateur
    }
  }

  /// Gère l'état de l'utilisateur après connexion
  Future<void> handleUserState(String uid) async {
    final user = _auth.currentUser;
    if (user == null) {
      Get.offAll(() => const LoginScreen());
      return;
    }

    await Future.delayed(const Duration(seconds: 1)); // ⏳ Attente pour éviter les conflits
    await user.reload();

    if (!user.emailVerified) {
      Get.offAll(() => const VerifyEmailScreen());
      return;
    }

    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (userDoc.exists) {
      _updateUserData(userDoc);
    } else {
      final pendingDoc = await _firestore.collection('pending_users').doc(uid).get();
      if (pendingDoc.exists) {
        await _migrateUserFromPending(uid);
      } else {
        _handleMissingUser();
      }
    }
  }

  /// Migration de l'utilisateur de `pending_users` vers `users`
  Future<void> _migrateUserFromPending(String uid) async {
    final pendingDoc = await _firestore.collection('pending_users').doc(uid).get();
    if (pendingDoc.exists) {
      await _firestore.collection('users').doc(uid).set(pendingDoc.data() as Map<String, dynamic>);
      await _firestore.collection('pending_users').doc(uid).delete();
    }
  }

  /// Met à jour les informations de l'utilisateur
  void _updateUserData(DocumentSnapshot userDoc) {
    if (userDoc.data() != null) {
      _user.value = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
      _updateFCMToken(userDoc.id);
      if (Get.currentRoute != '/main') {
        Get.offAll(() => const MainScreen());
      }
    }
  }

  /// Gère l'authentification après la connexion**
  Future<void> handleUserAuthentication(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (userDoc.exists) {
      _updateUserData(userDoc);
    } else {
      _handleMissingUser();
    }
  }

  /// Gestion des utilisateurs introuvables**
  void _handleMissingUser() {
    if (_auth.currentUser?.emailVerified ?? false) {
      _showSnackbar("Erreur", "Profil utilisateur introuvable", Colors.red);
      signOut();
    } else {
      Get.offAll(() => const VerifyEmailScreen());
    }
  }

  /// Met à jour le Token de Notification (FCM)
  Future<void> _updateFCMToken(String uid) async {
    try {
      String? fcmToken = await _messaging.getToken();
      if (fcmToken != null) {
        await _firestore.collection('users').doc(uid).update({'fcmToken': fcmToken});
      }
    } catch (e) {
      debugPrint(" Erreur mise à jour FCM : $e");
    }
  }

  /// Récupère la liste des utilisateurs en temps réel
  void _fetchAllUsers() {
    _firestore.collection('users').snapshots().listen((snapshot) {
      try {
        _userList.value = snapshot.docs
            .map((doc) => AppUser.fromMap(doc.data()))
            .where((user) => user.nom.trim().isNotEmpty)
            .toList();
        update();
      } catch (e) {
        debugPrint("Erreur récupération utilisateurs : $e");
      }
    }, onError: (error) {
      debugPrint("Erreur flux Firestore : $error");
    });
  }

  /// Déconnexion de l'utilisateur
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      _user.value = null;
      Get.offAll(() => const LoginScreen());
      _showSnackbar("Déconnexion", "Vous êtes déconnecté", Colors.green);
    } catch (e) {
      _showSnackbar("Erreur", "Échec de la déconnexion : $e", Colors.red);
    }
  }

  /// Affiche une notification snack
  void _showSnackbar(String title, String message, Color color) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: color,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }
}
