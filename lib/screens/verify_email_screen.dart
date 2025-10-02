// lib/screens/verify_email_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/user_controller.dart';
import '../services/email_link_handler.dart';
import '../services/verify_email_throttle.dart';
import '../theme/ad_colors.dart';
import 'main_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _isProcessing = true;
  String? _message;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Timer? _pollingTimer;
  StreamSubscription<void>? _linkSub;

  // Infos transmises depuis SignUp/Login (facultatif)
  bool _emailSent = false;
  int? _sentAtMs;

  static final ActionCodeSettings _acs = ActionCodeSettings(
    url: 'https://adfoot.org/verify',
    handleCodeInApp: false,
  );

  @override
  void initState() {
    super.initState();

    // Récupère d'éventuels arguments (ex: depuis SignUp)
    final args = Get.arguments;
    if (args is Map) {
      _emailSent = args['emailSent'] == true;
      _sentAtMs = args['sentAt'] is int ? args['sentAt'] as int : null;
      if (_sentAtMs != null) {
        // Seed du throttle pour éviter renvois multiples au démarrage
        VerifyEmailThrottle.lastSentAt =
            DateTime.fromMillisecondsSinceEpoch(_sentAtMs!);
      }
    }

    _listenToEmailVerification();

    _handlePossibleRedirectParams().then((_) {
      _startVerificationPolling();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  // --- WEB: appliqué si la page /verify contient ?mode=verifyEmail&oobCode=...
  Map<String, String> _mergedParamsFrom(Uri uri) {
    final params = <String, String>{...uri.queryParameters};
    if (uri.fragment.isNotEmpty) {
      try {
        params.addAll(Uri.splitQueryString(uri.fragment));
      } catch (_) {}
    }
    return params;
  }

  Future<void> _handlePossibleRedirectParams() async {
    if (!kIsWeb) return;

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

      // Après application du code, on tente de recharger l'utilisateur
      await _auth.currentUser?.reload();
      final user = _auth.currentUser;

      if (user == null) {
        // L’utilisateur a vérifié depuis un navigateur sans session active
        setState(() {
          _isProcessing = false;
          _message = "E-mail vérifié. Veuillez vous reconnecter pour continuer.";
        });
        return;
      }

      if (user.emailVerified) {
        await _syncUserFirestore(user);
        if (!mounted) return;

        await Get.offAll(() => const MainScreen());
        if (Get.isRegistered<UserController>()) {
          Get.find<UserController>().kickstart();
        }
        return;
      }
    }
  }

  void _listenToEmailVerification() {
    // Mobile (app links) : notification via EmailLinkHandler
    EmailLinkHandler.init().then((_) {
      _linkSub = EmailLinkHandler.onEmailVerified.listen((_) {
        _onEmailVerified();
      });
    });
  }

  void _startVerificationPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      final user = _auth.currentUser;
      if (user == null) return;
      await user.reload();
      final refreshed = _auth.currentUser;
      if (refreshed != null && refreshed.emailVerified) {
        _onEmailVerified();
      }
    });

    setState(() {
      _isProcessing = false;
      _message = _emailSent
          ? "Un e-mail de vérification a été envoyé. Clique sur le lien pour activer ton compte."
          : "Vérifie ta boîte mail et clique sur le lien pour activer ton compte.";
    });
  }

  Future<void> _onEmailVerified() async {
    _pollingTimer?.cancel();
    _linkSub?.cancel();

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _message = "Utilisateur non connecté.";
      });
      return;
    }

    await _syncUserFirestore(user);

    if (!mounted) return;
    await Get.offAll(() => const MainScreen());
    if (Get.isRegistered<UserController>()) {
      Get.find<UserController>().kickstart();
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
    if (!VerifyEmailThrottle.canSendNow()) {
      Get.snackbar(
        'Veuillez patienter',
        'Attendez quelques secondes avant de renvoyer.',
        backgroundColor: AdColors.warning,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Utilisateur non connecté');
      await user.sendEmailVerification(_acs);
      VerifyEmailThrottle.markSentNow();

      if (!mounted) return;
      Get.snackbar(
        'Lien envoyé',
        'Un e-mail de vérification a été renvoyé.',
        backgroundColor: AdColors.success,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      Get.snackbar(
        'Erreur',
        e.message ?? 'Erreur d’envoi.',
        backgroundColor: AdColors.error,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(
        'Erreur',
        e.toString(),
        backgroundColor: AdColors.error,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EEFA),
      appBar: AppBar(
        title: const Text('Vérification e-mail'),
        centerTitle: true,
        backgroundColor: const Color(0xFF214D4F),
        foregroundColor: Colors.white,
      ),
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
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _onEmailVerified,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text("J’ai cliqué sur le lien, continuer"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF214D4F),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _resendEmail,
                      icon: const Icon(Icons.email_outlined),
                      label: const Text("Renvoyer le lien de vérification"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade300,
                        foregroundColor: Colors.black87,
                        minimumSize: const Size(double.infinity, 48),
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
