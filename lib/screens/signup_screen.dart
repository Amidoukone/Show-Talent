// lib/screens/signup_screen.dart
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/verify_email_throttle.dart';
import '../utils/auth_error_mapper.dart';
import '../theme/ad_colors.dart';
import '../widgets/ad_text_field.dart';
import '../widgets/ad_button.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  // State
  final _formKey = GlobalKey<FormState>();
  String _selectedRole = 'joueur';
  bool _isLoading = false;

  static const _roles = ['joueur', 'club', 'recruteur', 'fan'];

  static final ActionCodeSettings _acs = ActionCodeSettings(
    // 👉 route /verify (main.dart) -> VerifyEmailScreen
    url: 'https://adfoot.org/verify',
    handleCodeInApp: false,
  );

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showSnackbar(String title, String msg, Color color) {
    Get.snackbar(
      title,
      msg,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: color,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.all(12),
      borderRadius: 12,
    );
  }

  Future<void> _signUp() async {
    // Ferme le clavier
    FocusScope.of(context).unfocus();

    // Validation
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final nom = _nameController.text.trim();
      final phone = _phoneController.text.trim();

      // 1) Création Auth
      final userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCred.user;
      if (user == null) {
        _showSnackbar('Erreur', 'Impossible de créer le compte.', AdColors.error);
        return;
      }

      // 2) Affichage du nom (Auth)
      if (nom.isNotEmpty) {
        await user.updateDisplayName(nom);
      }

      // 3) Création/merge du profil Firestore (idempotent)
      final now = DateTime.now();
      final appUser = AppUser(
        uid: user.uid,
        nom: nom,
        email: email,
        role: _selectedRole,
        photoProfil: '',
        estActif: false,
        estBloque: false,
        emailVerified: false,
        followers: 0,
        followings: 0,
        dateInscription: now,
        dernierLogin: now,
        phone: phone.isNotEmpty ? phone : null,
        emailVerifiedAt: null,
        bio: null,
        position: null,
        clubActuel: null,
        nombreDeMatchs: null,
        buts: null,
        assistances: null,
        videosPubliees: const [],
        performances: const {},
        nomClub: null,
        ligue: null,
        offrePubliees: const [],
        eventPublies: const [],
        entreprise: null,
        nombreDeRecrutements: null,
        team: null,
        joueursSuivis: const [],
        clubsSuivis: const [],
        videosLikees: const [],
        cvUrl: null,
        followersList: const [],
        followingsList: const [],
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(appUser.toMap(), SetOptions(merge: true));

      // 4) Email de vérification (avec seed du throttle)
      bool sent = false;
      int? sentAtMs;
      try {
        await user.sendEmailVerification(_acs);
        sent = true;
        sentAtMs = DateTime.now().millisecondsSinceEpoch;
        // Seed + start throttle pour éviter un renvoi immédiat
        VerifyEmailThrottle.lastSentAt = DateTime.fromMillisecondsSinceEpoch(sentAtMs);
        VerifyEmailThrottle.markSentNow();
      } on FirebaseAuthException catch (e) {
        // Infos seulement; on n’empêche pas d’aller à l’écran de vérif
        debugPrint('sendEmailVerification error: ${e.code} - ${e.message}');
        _showSnackbar(
          'Attention',
          'E-mail non envoyé. Tu pourras le renvoyer sur l’écran suivant.',
          AdColors.warning,
        );
      }

      // 5) Refresh Auth (sécurité)
      await FirebaseAuth.instance.currentUser?.reload();

      if (!mounted) return;

      // 6) Info utilisateur
      _showSnackbar(
        'Compte créé',
        sent
            ? 'Vérifie ton adresse e-mail pour activer ton compte.'
            : 'Compte créé. Renvoyez le lien depuis l’écran suivant.',
        AdColors.success,
      );

      // 7) Navigation vers VerifyEmailScreen (unifiée), avec arguments de cooldown
      Get.offAll(
        () => const VerifyEmailScreen(),
        arguments: {
          'emailSent': sent,
          'sentAt': sentAtMs,
        },
      );
    } on FirebaseAuthException catch (e) {
      _showSnackbar('Erreur', AuthErrorMapper.toMessage(e), AdColors.error);
    } catch (e) {
      _showSnackbar('Erreur', 'Une erreur inattendue s’est produite. Réessayez.', AdColors.error);
      debugPrint('SignUp unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                          child: Image.asset(
                            'assets/logo.png',
                            height: 80,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Créez un compte',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Rejoins la communauté AD.FOOT',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              // ⬇️ Remplacement withOpacity(...) -> withValues(alpha: ...)
                              color: cs.onSurface.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // Nom
                      AdTextField(
                        controller: _nameController,
                        label: 'Nom complet',
                        prefixIcon: const Icon(Icons.person_outline),
                        validator: _validateName,
                      ),
                      const SizedBox(height: 16),

                      // Email
                      AdTextField(
                        controller: _emailController,
                        label: 'Adresse e-mail',
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(Icons.email_outlined),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 16),

                      // Téléphone (optionnel)
                      AdTextField(
                        controller: _phoneController,
                        label: 'Numéro de téléphone (optionnel)',
                        keyboardType: TextInputType.phone,
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                      const SizedBox(height: 16),

                      // Mot de passe
                      AdTextField(
                        controller: _passwordController,
                        label: 'Mot de passe',
                        isPassword: true,
                        prefixIcon: const Icon(Icons.lock_outline),
                        validator: (val) => (val?.length ?? 0) < 6 ? 'Minimum 6 caractères' : null,
                      ),
                      const SizedBox(height: 16),

                      // Rôle (dropdown)
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Rôle',
                          prefixIcon: Icon(Icons.account_circle_outlined),
                        ),
                        items: _roles
                            .map((r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(r.capitalizeFirst!),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedRole = v ?? 'joueur'),
                      ),
                      const SizedBox(height: 24),

                      // CTA
                      AdButton(
                        label: 'S’inscrire',
                        onPressed: _isLoading ? null : _signUp,
                        loading: _isLoading,
                        leading: Icons.person_add_alt_1_rounded,
                        kind: AdButtonKind.primary,
                      ),

                      const SizedBox(height: 8),

                      // Lien vers login
                      TextButton(
                        onPressed: _isLoading ? null : () => Get.back(),
                        child: const Text('Déjà un compte ? Se connecter'),
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

  // --- Validators ---

  String? _validateName(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Le nom est requis';
    // Autorise lettres avec accents, espaces, apostrophes et tirets
    if (!RegExp(r"^[A-Za-zÀ-ÿ\s'’-]+$").hasMatch(value)) return 'Nom invalide';
    return null;
  }

  String? _validateEmail(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Email requis';
    if (!RegExp(r'^[\w\.\-+]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(value)) return 'Email invalide';
    return null;
  }
}
