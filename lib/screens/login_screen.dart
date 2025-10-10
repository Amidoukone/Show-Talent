// lib/screens/login_screen.dart
import 'package:adfoot/screens/signup_screen.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/user_controller.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/ad_colors.dart';
import '../widgets/ad_text_field.dart';
import '../widgets/ad_button.dart';
import '../utils/auth_error_mapper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // State
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus(); // Ferme le clavier

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final pass = _passwordController.text;

      final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );

      final user = userCred.user;
      if (user != null) {
        // Rafraîchir état et token
        await user.reload();
        final refreshed = FirebaseAuth.instance.currentUser;
        await refreshed?.getIdToken(true);

        // Sync métier (sans navigation)
        if (Get.isRegistered<AuthController>()) {
          await Get.find<AuthController>().handleAuthState(refreshed);
        }

        // Navigation immédiate
        if (refreshed != null && refreshed.emailVerified == true) {
          await Get.offAll(() => const MainScreen());
        } else {
          await Get.offAll(() => const VerifyEmailScreen());
        }

        // Hydratation UserController en arrière-plan
        if (Get.isRegistered<UserController>()) {
          Get.find<UserController>().kickstart();
        }
      }
    } on FirebaseAuthException catch (e) {
      _showErrorSnackbar(AuthErrorMapper.toMessage(e));
    } catch (e) {
      _showErrorSnackbar('Erreur inattendue : ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showErrorSnackbar('Veuillez saisir votre e-mail.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      Get.snackbar(
        'Succès',
        'E-mail de réinitialisation envoyé.',
        backgroundColor: AdColors.success,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(12),
        borderRadius: 12,
      );
    } on FirebaseAuthException catch (e) {
      _showErrorSnackbar(AuthErrorMapper.toMessage(e));
    } catch (e) {
      _showErrorSnackbar('Erreur : ${e.toString()}');
    }
  }

  void _showErrorSnackbar(String message) {
    Get.snackbar(
      'Connexion échouée',
      message,
      backgroundColor: AdColors.error,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.all(12),
      borderRadius: 12,
    );
  }

  // --- UI ---

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
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo + titre
                      Align(
                        alignment: Alignment.center,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset('assets/logo.png', height: 80, fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Connectez-vous',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ravi de vous revoir !',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              // remplace withOpacity(.7)
                              color: cs.onSurface.withValues(alpha: .7),
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // Email
                      AdTextField(
                        controller: _emailController,
                        label: 'Adresse e-mail',
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(Icons.email_outlined),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return 'E-mail requis';
                          final ok = RegExp(r'^[\w\.\-+]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(value);
                          if (!ok) return 'E-mail invalide';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Mot de passe
                      AdTextField(
                        controller: _passwordController,
                        label: 'Mot de passe',
                        isPassword: true,
                        prefixIcon: const Icon(Icons.lock_outline),
                        validator: (v) => (v == null || v.isEmpty) ? 'Mot de passe requis' : null,
                        onSubmitted: _login,
                      ),

                      // Mot de passe oublié
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading ? null : _resetPassword,
                          child: const Text('Mot de passe oublié ?'),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // CTA
                      AdButton(
                        label: 'Se connecter',
                        onPressed: _isLoading ? null : _login,
                        loading: _isLoading,
                        leading: Icons.login_rounded,
                        kind: AdButtonKind.primary,
                      ),

                      const SizedBox(height: 12),

                      // Lien inscription
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Nouveau ici ?',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  // remplace withOpacity(.8)
                                  color: cs.onSurface.withValues(alpha: .8),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          TextButton(
                            onPressed: _isLoading ? null : () => Get.to(() => const SignUpScreen()),
                            child: const Text('Créez un compte'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
