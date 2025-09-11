import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../controller/user_controller.dart';
import 'main_screen.dart';

class VerifyRedirectScreen extends StatefulWidget {
  const VerifyRedirectScreen({super.key});

  @override
  State<VerifyRedirectScreen> createState() => _VerifyRedirectScreenState();
}

class _VerifyRedirectScreenState extends State<VerifyRedirectScreen> {
  bool _isProcessing = true;
  String? _message;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _resendOnce = false;

  static final ActionCodeSettings _acs = ActionCodeSettings(
    url: 'https://adfoot.org/verify',
    handleCodeInApp: false,
  );

  Map<String, String> _mergedParamsFrom(Uri uri) {
    final params = <String, String>{...uri.queryParameters};
    if (uri.fragment.isNotEmpty) {
      try { params.addAll(Uri.splitQueryString(uri.fragment)); } catch (_) {}
    }
    return params;
  }

  @override
  void initState() {
    super.initState();
    _handleVerificationRedirect();
  }

  Future<void> _handleVerificationRedirect() async {
    try {
      if (kIsWeb) {
        final params = _mergedParamsFrom(Uri.base);
        final mode = params['mode'];
        final oobCode = params['oobCode'];

        if (mode == 'verifyEmail' && oobCode != null && oobCode.isNotEmpty) {
          try {
            await _auth.checkActionCode(oobCode);
            await _auth.applyActionCode(oobCode);
          } on FirebaseAuthException catch (e) {
            debugPrint('applyActionCode error: ${e.code} - ${e.message}');
          }
        }
      }

      await _auth.currentUser?.reload();
      final user = _auth.currentUser;

      if (user == null) {
        setState(() {
          _isProcessing = false;
          _message = "Veuillez vous connecter pour continuer.";
        });
        return;
      }

      if (user.emailVerified) {
        await _syncUserFirestore(user);
        if (!mounted) return;

        // 🚦 Navigation + réveil UserController
        await Get.offAll(() => const MainScreen());
        if (Get.isRegistered<UserController>()) {
          Get.find<UserController>().kickstart();
        }
        return;
      }

      setState(() {
        _isProcessing = false;
        _message = "Votre adresse e-mail n’est pas encore vérifiée.\n"
            "Vous pouvez demander un nouvel envoi du lien.";
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _message = "Erreur : $e";
      });
    }
  }

  Future<void> _syncUserFirestore(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    await userRef.set({
      'emailVerified': true,
      'estActif': true,
      'emailVerifiedAt': FieldValue.serverTimestamp(),
      'dernierLogin': DateTime.now(),
    }, SetOptions(merge: true));
  }

  Future<void> _resendEmail() async {
    if (_resendOnce) return;
    _resendOnce = true;

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Utilisateur non connecté.');
      await user.sendEmailVerification(_acs);

      if (!mounted) return;
      Get.snackbar(
        'Lien envoyé',
        'Un e-mail de vérification a été renvoyé.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      Get.snackbar(
        'Erreur',
        e.message ?? 'Erreur d’envoi.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(
        'Erreur',
        e.toString(),
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EEFA),
      body: Center(
        child: _isProcessing
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _message ?? 'Erreur inconnue.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _resendEmail,
                      icon: const Icon(Icons.mark_email_read_outlined),
                      label: const Text('Renvoyer le lien de vérification'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF214D4F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
