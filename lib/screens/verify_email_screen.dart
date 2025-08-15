import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/auth_controller.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthController _authController = Get.find();

  bool _isSending = false;
  bool _isChecking = false;
  int _cooldown = 0; // secondes restantes avant de pouvoir renvoyer
  Timer? _timer;

  // Reçu depuis SignUpScreen
  late final bool _emailSentInitially;
  late final int? _sentAtMs; // epoch ms quand l’envoi initial a REUSSI

  static final ActionCodeSettings _acs = ActionCodeSettings(
    url: 'https://adfoot.org/verify',
    handleCodeInApp: false,
  );

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    _emailSentInitially = (args is Map && args['emailSent'] == true);
    _sentAtMs = (args is Map && args['sentAt'] is int) ? args['sentAt'] as int : null;

    // ❌ Plus d’envoi auto ici.
    // Si l’e-mail a été envoyé à l’inscription, on met un petit cooldown UI (max 60s).
    // S’il n’a pas été envoyé, bouton actif immédiatement.
    _setupInitialCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

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

  Future<void> _sendVerificationEmail() async {
    if (_cooldown > 0 || _isSending) return;
    setState(() => _isSending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Utilisateur non connecté.');
      await user.sendEmailVerification(_acs);

      // Après un envoi réussi : cooldown léger 60s
      _startCooldown(60);

      Get.snackbar(
        'Lien envoyé',
        'Un e-mail de vérification a été envoyé.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') {
        // Backoff 180s UNIQUEMENT si Firebase bloque.
        _startCooldown(180);
        Get.snackbar(
          'Trop de tentatives',
          'Trop de demandes depuis cet appareil. Réessayez plus tard.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      } else {
        Get.snackbar(
          'Erreur',
          e.message ?? 'Erreur d’envoi.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Erreur',
        e.toString(),
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _checkEmailVerified() async {
    setState(() => _isChecking = true);

    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (user != null && user.emailVerified) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'emailVerified': true,
          'estActif': true,
          'emailVerifiedAt': FieldValue.serverTimestamp(),
          'dernierLogin': DateTime.now(),
        }, SetOptions(merge: true));

        await _authController.handleAuthState(user);

        Get.snackbar(
          'Merci',
          'Adresse e-mail vérifiée ✅',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      } else {
        Get.snackbar(
          'Non vérifié',
          'Clique sur le lien reçu par e-mail avant de continuer.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Erreur',
        e.toString(),
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFE6EEFA),
      appBar: AppBar(
        title: const Text('Vérification Email'),
        backgroundColor: const Color(0xFF214D4F),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo.png', height: 100),
                const SizedBox(height: 24),
                const Text(
                  'Vérifie ton e-mail',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF214D4F)),
                ),
                const SizedBox(height: 12),
                Text(
                  email.isNotEmpty
                      ? 'Un lien a été envoyé à :\n$email'
                      : 'Un lien de vérification a été envoyé.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF214D4F)),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: (_isSending || _cooldown > 0) ? null : _sendVerificationEmail,
                    icon: _isSending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.mark_email_read_outlined),
                    label: Text(
                      _cooldown > 0 ? 'Renvoyer dans $_cooldown s' : 'Renvoyer le lien',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF214D4F),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _isChecking ? null : _checkEmailVerified,
                  icon: _isChecking
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.verified),
                  label: const Text('J’ai cliqué le lien, continuer'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF214D4F)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),

                TextButton(
                  onPressed: _authController.signOut,
                  child: const Text('Changer de compte', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
