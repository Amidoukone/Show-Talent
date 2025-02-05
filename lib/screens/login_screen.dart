import 'package:adfoot/screens/main_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:adfoot/screens/signup_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showErrorSnackbar('Tous les champs doivent être remplis.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;
      await user?.reload(); // Recharger les données utilisateur
      user = FirebaseAuth.instance.currentUser;

      if (user != null && !user.emailVerified) {
        await FirebaseAuth.instance.signOut();
        await user.sendEmailVerification();
        _showErrorSnackbar('Veuillez vérifier votre email avant de vous connecter. Un nouvel e-mail a été envoyé.');
        return;
      }

      await _updateFcmToken(user);
      _showSuccessSnackbar('Connexion réussie');
      Get.offAll(() => const MainScreen());
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } catch (e) {
      _showErrorSnackbar('Erreur inattendue : $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateFcmToken(User? user) async {
    if (user == null) return;

    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'fcmToken': token},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      print("Erreur lors de la mise à jour du token FCM : $e");
    }
  }

  Future<void> _forgotPassword() async {
    if (_emailController.text.isEmpty) {
      _showErrorSnackbar('Veuillez entrer votre email pour réinitialiser le mot de passe.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _emailController.text.trim());
      _showSuccessSnackbar('Un email de réinitialisation vous a été envoyé.');
    } catch (e) {
      _showErrorSnackbar("Impossible d'envoyer l'email de réinitialisation. Veuillez réessayer.");
    }
  }

  void _handleAuthError(FirebaseAuthException e) {
    String errorMessage = 'Impossible de se connecter.';
    if (e.code == 'user-not-found') {
      errorMessage = 'Utilisateur introuvable. Vérifiez vos informations.';
    } else if (e.code == 'wrong-password') {
      errorMessage = 'Mot de passe incorrect.';
    } else if (e.code == 'invalid-email') {
      errorMessage = 'Adresse e-mail invalide.';
    }
    _showErrorSnackbar(errorMessage);
  }

  void _showSuccessSnackbar(String message) {
    Get.snackbar('Succès', message, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.green, colorText: Colors.white);
  }

  void _showErrorSnackbar(String message) {
    Get.snackbar('Erreur', message, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EEFA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset('assets/logo.png', height: 100),
              const SizedBox(height: 40),
              const Text('Connectez-vous!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF214D4F))),
              const SizedBox(height: 20),
              TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Adresse e-mail', prefixIcon: Icon(Icons.email))),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgotPassword,
                  child: const Text('Mot de passe oublié ?', style: TextStyle(color: Color(0xFF214D4F))),
                ),
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _login,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: const Text('Se connecter', style: TextStyle(fontSize: 16, color: Colors.white)),
                    ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Get.to(() => const SignUpScreen()),
                child: const Text("Vous n'avez pas de compte ? Inscrivez-vous", style: TextStyle(color: Color(0xFF214D4F))),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 