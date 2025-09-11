import 'package:adfoot/screens/login_screen.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/auth_controller.dart';
import '../controller/user_controller.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _navigating = false;
  late final bool _authControllerPresent;

  @override
  void initState() {
    super.initState();
    _authControllerPresent = Get.isRegistered<AuthController>();

    // Si AuthController est présent, c’est UserController qui navigue.
    // On le "réveille" après le 1er frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Get.find<UserController>().kickstart();
      } catch (_) {}
    });

    // Si jamais AuthController n'est pas présent (tests/démo), on route ici.
    if (!_authControllerPresent) {
      _initializeFallback();
    }
  }

  Future<void> _initializeFallback() async {
    // Petit délai pour laisser Firebase s'initialiser correctement
    await Future.delayed(const Duration(milliseconds: 600));

    try {
      final currentUser = _auth.currentUser;

      if (currentUser == null) {
        return _safeOffAll(const LoginScreen());
      }

      await currentUser.reload();
      final refreshedUser = _auth.currentUser;

      if (refreshedUser == null) {
        return _safeOffAll(const LoginScreen());
      }

      if (!refreshedUser.emailVerified) {
        return _safeOffAll(const VerifyEmailScreen());
      }

      final docRef = _firestore.collection('users').doc(refreshedUser.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        await _auth.signOut();
        return _safeOffAll(const LoginScreen());
      }

      // Sync minime
      final data = doc.data()!;
      final updates = <String, dynamic>{};
      if (data['emailVerified'] != true) updates['emailVerified'] = true;
      if (data['estActif'] != true) updates['estActif'] = true;
      if (data['emailVerifiedAt'] == null) {
        updates['emailVerifiedAt'] = FieldValue.serverTimestamp();
      }
      if (updates.isNotEmpty) {
        await docRef.update(updates);
      }

      return _safeOffAll(const MainScreen());
    } catch (e) {
      debugPrint('Splash fallback error: $e');
      try {
        await _auth.signOut();
      } catch (_) {}
      return _safeOffAll(const LoginScreen());
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

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF214D4F),
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
