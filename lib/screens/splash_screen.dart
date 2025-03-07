import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/login_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import '../controller/auth_controller.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthController _authController = Get.find<AuthController>();

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  /// Vérifie l'état de l'authentification avant de naviguer
Future<void> _checkAuthState() async {
  await Future.delayed(const Duration(seconds: 2)); // Pause pour chargement

  FirebaseAuth.instance.authStateChanges().listen((User? user) async {
    if (user == null) {
      Get.offAll(() => const LoginScreen());
      return;
    }

    await user.reload();
    user = FirebaseAuth.instance.currentUser;

    if (!user!.emailVerified) {
      Get.offAll(() => const VerifyEmailScreen());
      return;
    }

    final exists = await _authController.userExistsInDatabase(user.uid);
    if (exists) {
      Get.offAll(() => const MainScreen());
    } else {
      await _authController.signOut();
    }
  });
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