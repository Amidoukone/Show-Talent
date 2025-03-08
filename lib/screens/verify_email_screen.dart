import 'package:adfoot/controller/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:io';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthController _authController = Get.find<AuthController>();
  bool _isLoading = false;

  ///Vérifie si l'email est validé et redémarre l'application
  Future<void> _completeVerification() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    bool success = await _authController.verifyEmail();

    if (!mounted) return; // Évite l'erreur setState() after dispose
    setState(() => _isLoading = false);

    if (!success) {
      _showSnackbar('Erreur', 'Votre email n\'est pas encore validé.', Colors.red);
      return;
    }

    /// Redémarrage automatique après validation de l'email
    _restartApp();
  }

  /// Force le redémarrage de l’application en fermant puis relançant
  void _restartApp() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (Platform.isAndroid) {
        exit(0); // Ferme l'application sur Android
      } else {
        Get.offAllNamed('/'); // Redémarrage manuel pour iOS (pas d'exit direct)
      }
    });
  }

  /// Renvoyer l'email de vérification
  Future<void> _resendVerification() async {
    setState(() => _isLoading = true);

    final success = await _authController.resendVerificationEmail();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      _showSnackbar('Succès', 'Email de validation renvoyé !', Colors.green);
    } else {
      _showSnackbar('Erreur', 'Échec de l\'envoi.', Colors.red);
    }
  }

  /// Affiche une notification snack
  void _showSnackbar(String title, String message, Color color) {
    Get.snackbar(title, message, backgroundColor: color, colorText: Colors.white);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vérification Email'),
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 80, color: Color(0xFF214D4F)),
              const SizedBox(height: 30),
              const Text('Finalisez votre inscription',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF214D4F))),
              const SizedBox(height: 20),
              const Text(
                '1. Vérifiez votre boîte mail et cliquez sur le lien de confirmation.\n\n'
                '2. Revenez ici et cliquez sur "J\'ai validé mon email".\n\n',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 40),
              _isLoading
                  ? const CircularProgressIndicator(color: Color(0xFF214D4F))
                  : ElevatedButton(
                      onPressed: _completeVerification,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF214D4F),
                      ),
                      child: const Text("J'ai validé mon email"),
                    ),
              TextButton(
                onPressed: _resendVerification,
                child: const Text('Renvoyer l\'email de vérification', style: TextStyle(color: Color(0xFF214D4F))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
