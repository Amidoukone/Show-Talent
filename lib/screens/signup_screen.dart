import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String _selectedRole = 'joueur';
  bool _obscurePassword = true;
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();

  static final ActionCodeSettings _acs = ActionCodeSettings(
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
      title, msg,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: color,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final nom = _nameController.text.trim();
      final phone = _phoneController.text.trim();

      final userCred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = userCred.user;
      if (user == null) {
        _showSnackbar('Erreur', 'Impossible de créer le compte.', Colors.red);
        return;
      }

      await user.updateDisplayName(nom);

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
          .set(appUser.toMap());

      bool sent = false;
      int? sentAtMs;
      try {
        await user.sendEmailVerification(_acs);
        sent = true;
        sentAtMs = DateTime.now().millisecondsSinceEpoch;
      } on FirebaseAuthException catch (e) {
        // Si rate-limit ou autre à l’inscription, on n’insiste pas ici
        debugPrint('sendEmailVerification error: ${e.code} - ${e.message}');
        _showSnackbar(
          'Attention',
          'E-mail non envoyé. Tu pourras le renvoyer sur l’écran suivant.',
          Colors.orange,
        );
      }

      await FirebaseAuth.instance.currentUser?.reload();

      if (!mounted) return;
      _showSnackbar(
        'Compte créé',
        sent
            ? 'Vérifie ton adresse e-mail pour activer ton compte.'
            : 'Compte créé. Renvoyez le lien depuis l’écran suivant.',
        Colors.green,
      );

      // ⚠️ On passe l’état d’envoi au prochain écran
      Get.offAll(
        () => const VerifyEmailScreen(),
        arguments: {
          'emailSent': sent,
          'sentAt': sentAtMs, // utilisé pour afficher un cooldown UI max 60s SEULEMENT si sent==true
        },
      );
    } on FirebaseAuthException catch (e) {
      String err = switch (e.code) {
        'email-already-in-use' => 'Email déjà utilisé.',
        'weak-password' => 'Mot de passe trop court.',
        'invalid-email' => 'Email invalide.',
        'operation-not-allowed' => 'Inscription par e-mail désactivée.',
        _ => e.message ?? 'Erreur. Réessaye.'
      };
      _showSnackbar('Erreur', err, Colors.red);
    } catch (e) {
      _showSnackbar('Erreur', e.toString(), Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EEFA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Image.asset('assets/logo.png', height: 100),
                const SizedBox(height: 30),
                const Text(
                  'Créez un compte',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF214D4F)),
                ),
                const SizedBox(height: 30),
                _buildTextField(_nameController, 'Nom complet', Icons.person_outline, validator: _validateName),
                const SizedBox(height: 20),
                _buildTextField(
                  _emailController,
                  'Adresse email',
                  Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: _validateEmail,
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  _phoneController,
                  'Numéro de téléphone',
                  Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 20),
                _buildPasswordField(),
                const SizedBox(height: 20),
                _buildRoleDropdown(),
                const SizedBox(height: 30),
                _buildSubmitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: validator,
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Mot de passe',
        prefixIcon: const Icon(Icons.lock_outline),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: IconButton(
          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (val) => (val?.length ?? 0) < 6 ? 'Minimum 6 caractères' : null,
    );
  }

  Widget _buildRoleDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedRole,
      decoration: InputDecoration(
        labelText: 'Rôle',
        prefixIcon: const Icon(Icons.account_circle_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: ['joueur', 'club', 'recruteur', 'fan']
          .map((r) => DropdownMenuItem(value: r, child: Text(r.capitalizeFirst!)))
          .toList(),
      onChanged: (v) => setState(() => _selectedRole = v ?? 'joueur'),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signUp,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF214D4F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text('S’inscrire', style: TextStyle(fontSize: 18, color: Colors.white)),
      ),
    );
  }

  String? _validateName(String? v) {
    if ((v?.trim().isEmpty ?? true)) return 'Le nom est requis';
    if (!RegExp(r"^[A-Za-zÀ-ÿ\s'-]+$").hasMatch(v!)) return 'Nom invalide';
    return null;
  }

  String? _validateEmail(String? v) {
    if ((v?.trim().isEmpty ?? true)) return 'Email requis';
    if (!RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(v!)) return 'Email invalide';
    return null;
  }
}
