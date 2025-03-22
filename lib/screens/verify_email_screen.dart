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

  Future<void> _completeVerification() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    await _refreshCurrentUser();

    bool success = await _authController.verifyEmail();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!success) {
      _showSnackbar('Erreur', 'Votre email n\'est pas encore validé.', Colors.red);
      return;
    }

    _restartApp();
  }

  Future<void> _refreshCurrentUser() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      await _authController.auth.currentUser?.reload();
    } catch (e) {
      debugPrint('Erreur de rechargement utilisateur : $e');
    }
  }

  void _restartApp() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (Platform.isAndroid) {
        exit(0);
      } else {
        Get.offAllNamed('/');
      }
    });
  }

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

  void _showSnackbar(String title, String message, Color color) {
    Get.snackbar(title, message, backgroundColor: color, colorText: Colors.white);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EEFA),
      appBar: AppBar(
        title: const Text('Vérification Email'),
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 80, color: Color(0xFF214D4F)),
              const SizedBox(height: 30),
              const Text(
                'Finalisez votre inscription',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF214D4F),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '1. Vérifiez votre boîte mail et cliquez sur le lien de confirmation.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                '2. Revenez ici et cliquez sur "J\'ai validé mon email".',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                '3. L\'application se fermera automatiquement après validation. Veuillez la relancer.',
                style: TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              _isLoading
                  ? const CircularProgressIndicator(color: Color(0xFF214D4F))
                  : SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _completeVerification,
                        style: ElevatedButton.styleFrom(
                          elevation: 4,
                          backgroundColor: const Color(0xFF214D4F),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "J'ai validé mon email",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _resendVerification,
                child: const Text(
                  'Renvoyer l\'email de vérification',
                  style: TextStyle(
                    color: Color(0xFF214D4F),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
