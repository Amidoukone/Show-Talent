import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/ad_colors.dart';
import '../widgets/ad_text_field.dart';
import '../widgets/ad_button.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String oobCode;

  const ResetPasswordScreen({super.key, required this.oobCode});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;

  Future<void> _resetPassword() async {
    final pass = _passwordController.text;
    final confirm = _confirmController.text;

    if (pass.length < 6) {
      Get.snackbar('Erreur', 'Le mot de passe doit contenir au moins 6 caractères.',
          backgroundColor: AdColors.error, colorText: Colors.white);
      return;
    }
    if (pass != confirm) {
      Get.snackbar('Erreur', 'Les mots de passe ne correspondent pas.',
          backgroundColor: AdColors.error, colorText: Colors.white);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.confirmPasswordReset(
        code: widget.oobCode,
        newPassword: pass,
      );

      Get.snackbar(
        'Succès',
        'Mot de passe réinitialisé avec succès.',
        backgroundColor: AdColors.success,
        colorText: Colors.white,
      );

      // Redirige vers connexion
      Get.offAll(() => const LoginScreen());
    } on FirebaseAuthException catch (e) {
      Get.snackbar(
        'Erreur',
        e.message ?? 'Impossible de réinitialiser le mot de passe.',
        backgroundColor: AdColors.error,
        colorText: Colors.white,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      'Réinitialiser le mot de passe',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                    ),
                    const SizedBox(height: 24),
                    AdTextField(
                      controller: _passwordController,
                      label: 'Nouveau mot de passe',
                      isPassword: true,
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    const SizedBox(height: 16),
                    AdTextField(
                      controller: _confirmController,
                      label: 'Confirmer le mot de passe',
                      isPassword: true,
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    const SizedBox(height: 24),
                    AdButton(
                      label: 'Valider',
                      onPressed: _isLoading ? null : _resetPassword,
                      loading: _isLoading,
                      kind: AdButtonKind.primary,
                      leading: Icons.check_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
