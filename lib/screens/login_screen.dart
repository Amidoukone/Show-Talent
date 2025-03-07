import 'package:adfoot/screens/signup_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/user_controller.dart';

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
  final UserController _userController = Get.find<UserController>();

Future<void> _login() async {
  if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
    _showErrorSnackbar('Tous les champs doivent être remplis.');
    return;
  }

  setState(() => _isLoading = true);

  try {
    final UserCredential userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    final User? user = userCred.user;
    await user?.reload();
    final User? refreshedUser = FirebaseAuth.instance.currentUser;

    if (refreshedUser == null || !refreshedUser.emailVerified) {
      await _handleUnverifiedUser(refreshedUser);
      return;
    }

    await _updateFcmToken(refreshedUser);
    await _userController.handleUserAuthentication(refreshedUser.uid); // 🔄 Utilisation de la méthode publique corrigée

  } on FirebaseAuthException catch (e) {
    _handleAuthError(e);
  } catch (e) {
    _showErrorSnackbar('Erreur inattendue : ${e.toString()}');
  } finally {
    setState(() => _isLoading = false);
  }
}


  Future<void> _handleUnverifiedUser(User? user) async {
    await FirebaseAuth.instance.signOut();
    if (user != null) {
      await user.sendEmailVerification();
      _showErrorSnackbar(
        'Validation requise',
        'Veuillez vérifier votre email. Un nouveau lien a été envoyé.',
      );
    }
  }

  Future<void> _updateFcmToken(User user) async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'fcmToken': token},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint("Erreur FCM : $e");
    }
  }

  Future<void> _forgotPassword() async {
    if (_emailController.text.isEmpty) {
      _showErrorSnackbar('Veuillez saisir votre email');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim()
      );
      _showSuccessSnackbar('Email de réinitialisation envoyé');
    } catch (e) {
      _showErrorSnackbar('Erreur lors de l\'envoi de l\'email');
    }
  }

  void _handleAuthError(FirebaseAuthException e) {
    String message = 'Erreur de connexion';
    switch (e.code) {
      case 'user-not-found':
        message = 'Aucun compte associé à cet email';
        break;
      case 'wrong-password':
        message = 'Mot de passe incorrect';
        break;
      case 'invalid-email':
        message = 'Format d\'email invalide';
        break;
      case 'too-many-requests':
        message = 'Trop de tentatives. Réessayez plus tard';
        break;
    }
    _showErrorSnackbar(message);
  }

  void _showSuccessSnackbar(String message) {
    Get.snackbar(
      'Succès',
      message,
      backgroundColor: Colors.green,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void _showErrorSnackbar(String title, [String? message]) {
    Get.snackbar(
      title,
      message ?? '',
      backgroundColor: Colors.red,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
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
              const Text(
                'Connectez-vous!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF214D4F),
                ),
              ),
              const SizedBox(height: 20),
              _buildEmailField(),
              const SizedBox(height: 20),
              _buildPasswordField(),
              const SizedBox(height: 10),
              _buildForgotPassword(),
              const SizedBox(height: 20),
              _buildLoginButton(),
              const SizedBox(height: 20),
              _buildSignUpLink(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Adresse e-mail',
        prefixIcon: Icon(Icons.email),
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Mot de passe',
        prefixIcon: const Icon(Icons.lock),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(_obscurePassword 
              ? Icons.visibility_off 
              : Icons.visibility),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    );
  }

  Widget _buildForgotPassword() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: _forgotPassword,
        child: const Text(
          'Mot de passe oublié ?',
          style: TextStyle(color: Color(0xFF214D4F)),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return _isLoading
        ? const CircularProgressIndicator()
        : ElevatedButton(
            onPressed: _login,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: const Color(0xFF214D4F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Se connecter',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          );
  }

  Widget _buildSignUpLink() {
    return TextButton(
      onPressed: () => Get.to(() => const SignUpScreen()),
      child: RichText(
        text: const TextSpan(
          text: 'Nouveau ici ? ',
          style: TextStyle(color: Color(0xFF214D4F)),
          children: <TextSpan>[
            TextSpan(
              text: 'Créez un compte',
              style: TextStyle(
                color: Color(0xFF214D4F),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 