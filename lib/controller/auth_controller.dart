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

  /// ✅ Getter public pour exposer FirebaseAuth
  FirebaseAuth get auth => _auth;

  /// ✅ Indique si l'utilisateur est connecté et prêt
  bool get isLoggedIn => _appUser.value != null && _firebaseUser.value != null;

  /// ✅ Récupère l'UID actuel
  String? get currentUid => _appUser.value?.uid;

  @override
  void onReady() {
    super.onReady();
    _firebaseUser.value = _auth.currentUser;
    _firebaseUser.bindStream(_auth.authStateChanges());
    ever(_firebaseUser, handleAuthState);
  }

  Future<void> handleAuthState(User? user) async {
    if (user == null) {
      _appUser.value = null;
      Get.offAll(() => const LoginScreen());
      return;
    }

    await Future.delayed(const Duration(seconds: 1));
    await user.reload();
    user = _auth.currentUser;

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

  Future<bool> verifyEmail() async {
    User? user = _auth.currentUser;
    if (user == null) return false;

    await user.reload();
    if (user.emailVerified) {
      await _migrateUserFromPending(user.uid);
      return true;
    }
    return false;
  }

  Future<bool> userExistsInDatabase(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    return userDoc.exists;
  }

  Future<void> _migrateUserFromPending(String uid) async {
    final pendingDoc = await _firestore.collection('pending_users').doc(uid).get();
    if (pendingDoc.exists) {
      final data = pendingDoc.data() as Map<String, dynamic>;
      await _firestore.collection('users').doc(uid).set(data);
      await _firestore.collection('pending_users').doc(uid).delete();
    }
  }

  Future<bool> resendVerificationEmail() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
      return true;
    } catch (e) {
      _showSnackbar('Erreur', 'Échec de l\'envoi : $e', Colors.red);
      return false;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _appUser.value = null;
    Get.offAll(() => const LoginScreen());
  }

  void _showSnackbar(String title, String message, Color color) {
    Get.snackbar(title, message, backgroundColor: color, colorText: Colors.white);
  }
}
