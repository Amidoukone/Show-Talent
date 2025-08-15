import 'package:adfoot/screens/login_screen.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/auth_controller.dart';
import 'dart:html' as html; // Ajout pour recharger la page web

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _navigating = false;
  late final bool _shouldRouteHere;
  String? _errorMessage; // Pour afficher une erreur en cas de problème

  @override
  void initState() {
    super.initState();
    // Si AuthController est enregistré, on lui laisse 100% la main sur la navigation
    _shouldRouteHere = !Get.isRegistered<AuthController>();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    if (!_shouldRouteHere) return; // Laisse AuthController router

    // Petit délai pour laisser Firebase s'initialiser correctement
    await Future.delayed(const Duration(seconds: 2));

    try {
      final currentUser = _auth.currentUser;

      // ⛔️ Pas connecté → Login
      if (currentUser == null) {
        return _safeOffAll(const LoginScreen());
      }

      // 🔄 Rafraîchir l'état Firebase (emailVerified, etc.)
      await currentUser.reload();
      final refreshedUser = _auth.currentUser;

      if (refreshedUser == null) {
        return _safeOffAll(const LoginScreen());
      }

      // ✉️ Email non vérifié → on laisse VerifyEmailScreen gérer l'envoi/renvoi
      if (!refreshedUser.emailVerified) {
        return _safeOffAll(const VerifyEmailScreen());
      }

      // 🔎 Récupérer le profil Firestore
      final docRef = _firestore.collection('users').doc(refreshedUser.uid);
      final doc = await docRef.get();

      // Cas rare : pas de profil → déconnexion propre
      if (!doc.exists) {
        await _auth.signOut();
        return _safeOffAll(const LoginScreen());
      }

      // ✅ Si vérifié côté Auth, synchroniser les champs Firestore si besoin
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

      // 🏠 Tout est ok → Main
      return _safeOffAll(const MainScreen());
    } catch (e) {
      // En cas d'erreur, on retourne au Login proprement
      debugPrint('Splash _initializeUser error: $e');
      try {
        await _auth.signOut();
      } catch (_) {}

      setState(() {
        _errorMessage =
            "Erreur au démarrage : ${e.toString()}\nEssayez de rafraîchir la page ou de vérifier votre connexion.";
      });
    }
  }

  Future<void> _safeOffAll(Widget page) async {
    if (_navigating) return;
    _navigating = true;
    try {
      // Utilise Get.offAll pour une navigation robuste sans doublons
      await Get.offAll(() => page);
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF214D4F),
      body: Center(
        child: _errorMessage != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      html.window.location.reload();
                    },
                    child: const Text("Rafraîchir la page"),
                  ),
                ],
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}