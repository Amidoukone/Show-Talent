import 'dart:async';
import 'dart:io';
import 'package:adfoot/screens/login_screen.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/user.dart';

class AuthController extends GetxController {
  static AuthController instance = Get.find();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Rx<User?> _firebaseUser = Rx<User?>(null);
  final Rx<AppUser?> _appUser = Rx<AppUser?>(null);
  File? _pickedImage;

  AppUser? get user => _appUser.value;
  File? get profilePhoto => _pickedImage;

  @override
  void onReady() {
    super.onReady();
    _firebaseUser.value = _auth.currentUser;
    _firebaseUser.bindStream(_auth.authStateChanges());
    ever(_firebaseUser, handleAuthState); // ✅ Devient public
  }

  /// 🔄 **Correction : Méthode rendue publique**
  Future<void> handleAuthState(User? user) async {
    if (user == null) {
      _appUser.value = null;
      Get.offAll(() => const LoginScreen());
      return;
    }

    await Future.delayed(const Duration(seconds: 1)); // Pause pour éviter les conflits
    await user.reload();
    user = _auth.currentUser; // Rafraîchir l'utilisateur

    if (!user!.emailVerified) {
      Get.offAll(() => const VerifyEmailScreen());
      return;
    }

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final pendingDoc = await _firestore.collection('pending_users').doc(user.uid).get();

    if (pendingDoc.exists) {
      await _migrateUserFromPending(user.uid);
    } else if (userDoc.exists) {
      _appUser.value = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
      Get.offAll(() => const MainScreen());
    } else {
      await signOut();
    }
  }

  /// ✅ Vérifie si l'email est validé et migre l'utilisateur
Future<bool> verifyEmail() async {
  User? user = _auth.currentUser;
  if (user == null) return false;

  await user.reload();
  if (user.emailVerified) {
    await _migrateUserFromPending(user.uid);
    return true; // ✅ On ne redirige pas ici, c'est géré dans VerifyEmailScreen
  }
  return false;
}


  /// 🔄 Vérifie si l'utilisateur existe dans Firestore (⚡ Réintégré)
  Future<bool> userExistsInDatabase(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    return userDoc.exists;
  }

  /// 🔄 Migration d'un utilisateur de pending_users vers users
  Future<void> _migrateUserFromPending(String uid) async {
    final pendingDoc = await _firestore.collection('pending_users').doc(uid).get();
    if (pendingDoc.exists) {
      final data = pendingDoc.data() as Map<String, dynamic>;
      await _firestore.collection('users').doc(uid).set(data);
      await _firestore.collection('pending_users').doc(uid).delete();
    }
  }

  /// 📩 Envoi d'un nouvel email de vérification
  Future<bool> resendVerificationEmail() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
      return true;
    } catch (e) {
      _showSnackbar('Erreur', 'Échec de l\'envoi : $e', Colors.red);
      return false;
    }
  }

  /// 🔓 Déconnexion de l'utilisateur
  Future<void> signOut() async {
    await _auth.signOut();
    _appUser.value = null;
    Get.offAll(() => const LoginScreen());
  }

  /// 🛑 Affichage des messages d'erreur/succès
  void _showSnackbar(String title, String message, Color color) {
    Get.snackbar(title, message, backgroundColor: color, colorText: Colors.white);
  }
}
