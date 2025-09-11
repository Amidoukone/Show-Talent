// lib/screens/verify_email_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/auth_controller.dart';
import '../controller/user_controller.dart';
import '../theme/ad_colors.dart';
import '../widgets/ad_button.dart';
import 'main_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthController _authController = Get.find();

  bool _isSending = false;
  bool _isChecking = false;
  int _cooldown = 0; // secondes restantes avant renvoi autorisé
  Timer? _timer;

  // Reçu depuis SignUpScreen
  late final bool _emailSentInitially;
  late final int? _sentAtMs; // epoch ms quand l’envoi initial a RÉUSSI

  static final ActionCodeSettings _acs = ActionCodeSettings(
    url: 'https://adfoot.org/verify',
    handleCodeInApp: false,
  );

  bool _navigating = false;

  @override
  void initState() {
    super.initState();

    final args = Get.arguments;
    _emailSentInitially = (args is Map && args['emailSent'] == true);
    _sentAtMs = (args is Map && args['sentAt'] is int) ? args['sentAt'] as int : null;

    _setupInitialCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // --- Cooldown & timers ---

  void _setupInitialCooldown() {
    if (_emailSentInitially && _sentAtMs != null) {
      final elapsed = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(_sentAtMs))
          .inSeconds;
      final remain = 60 - elapsed;
      if (remain > 0) {
        _startCooldown(remain);
      }
    }
  }

  void _startCooldown(int sec) {
    setState(() => _cooldown = sec);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  // --- Actions ---

  Future<void> _sendVerificationEmail() async {
    if (_cooldown > 0 || _isSending) return;
    setState(() => _isSending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Utilisateur non connecté.');
      await user.sendEmailVerification(_acs);

      _startCooldown(60);

      Get.snackbar(
        'Lien envoyé',
        'Un e-mail de vérification a été envoyé.',
        backgroundColor: AdColors.success,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(12),
        borderRadius: 12,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') {
        _startCooldown(180);
        Get.snackbar(
          'Trop de tentatives',
          'Trop de demandes depuis cet appareil. Réessayez plus tard.',
          backgroundColor: AdColors.warning,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(12),
          borderRadius: 12,
        );
      } else {
        Get.snackbar(
          'Erreur',
          e.message ?? 'Erreur d’envoi.',
          backgroundColor: AdColors.error,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(12),
          borderRadius: 12,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Erreur',
        e.toString(),
        backgroundColor: AdColors.error,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(12),
        borderRadius: 12,
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _navigateToMain() async {
    if (_navigating) return;
    _navigating = true;
    try {
      // Si le navigator n’est pas prêt, on postpose d’un frame
      if (Get.key.currentState == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) {
            await Get.offAll(() => const MainScreen());
          }
        });
      } else {
        await Get.offAll(() => const MainScreen());
      }
    } finally {
      _navigating = false;
    }
  }

  Future<void> _checkEmailVerified() async {
    setState(() => _isChecking = true);

    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (user != null && user.emailVerified) {
        // ✅ Sync Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'emailVerified': true,
          'estActif': true,
          'emailVerifiedAt': FieldValue.serverTimestamp(),
          'dernierLogin': DateTime.now(),
        }, SetOptions(merge: true));

        // 🔧 Sync métier (FCM, etc.) — ne navigue pas
        await _authController.handleAuthState(user);

        // ✅ Info
        Get.snackbar(
          'Merci',
          'Adresse e-mail vérifiée ✅',
          backgroundColor: AdColors.success,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(12),
          borderRadius: 12,
        );

        // 🚦 Navigation immédiate + réveil UserController
        await _navigateToMain();
        if (Get.isRegistered<UserController>()) {
          Get.find<UserController>().kickstart();
        }
      } else {
        Get.snackbar(
          'Non vérifié',
          'Clique sur le lien reçu par e-mail avant de continuer.',
          backgroundColor: AdColors.warning,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(12),
          borderRadius: 12,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Erreur',
        e.toString(),
        backgroundColor: AdColors.error,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(12),
        borderRadius: 12,
      );
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Vérification e-mail'),
        centerTitle: true,
      ),
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
                      'Vérifie ton e-mail',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ouvre le lien reçu pour activer ton compte.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(.7),
                            fontWeight: FontWeight.w600,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    // Email info
                    if (email.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outline, width: 1),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.email_outlined, color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                email,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 20),

                    // CTA principal : j'ai cliqué le lien
                    AdButton(
                      label: 'J’ai cliqué le lien, continuer',
                      onPressed: _isChecking ? null : _checkEmailVerified,
                      loading: _isChecking,
                      leading: Icons.verified_rounded,
                      kind: AdButtonKind.primary,
                    ),

                    const SizedBox(height: 12),

                    // CTA secondaire : renvoyer lien (avec cooldown)
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: (_isSending || _cooldown > 0) ? null : _sendVerificationEmail,
                        icon: _isSending
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AdColors.brand),
                              )
                            : const Icon(Icons.mark_email_read_outlined),
                        label: Text(
                          _cooldown > 0 ? 'Renvoyer dans $_cooldown s' : 'Renvoyer le lien',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdColors.brand,
                          side: const BorderSide(color: AdColors.brand, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Changer de compte
                    TextButton(
                      onPressed: _authController.signOut,
                      child: const Text('Changer de compte', style: TextStyle(color: Colors.red)),
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
