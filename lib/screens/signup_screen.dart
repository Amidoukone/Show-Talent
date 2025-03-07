
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/user.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  String _selectedRole = 'joueur';
  bool _obscurePassword = true;
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();

  void _showSnackbar(String title, String message, Color color) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: color,
      colorText: Colors.white,
      duration: const Duration(seconds: 3)
    );
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      final User? user = userCredential.user;
      if (user != null) {
        await user.sendEmailVerification();

        final newUser = AppUser(
          uid: user.uid,
          nom: _nameController.text.trim(),
          email: _emailController.text.trim(),
          role: _selectedRole,
          photoProfil: '',
          estActif: true,
          estBloque: false,
          followers: 0,
          followings: 0,
          dateInscription: DateTime.now(),
          dernierLogin: DateTime.now(),
          followersList: [],
          followingsList: [],
        );

        await FirebaseFirestore.instance
            .collection('pending_users')
            .doc(user.uid)
            .set(newUser.toMap());

        Get.offAll(() => const VerifyEmailScreen());
        _showSnackbar('Succès', 'Vérifiez votre email pour activer le compte', Colors.green);
      }
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } catch (e) {
      _showSnackbar('Erreur', 'Une erreur inattendue est survenue : ${e.toString()}', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleAuthError(FirebaseAuthException e) {
    String errorMessage = 'Échec de l\'inscription';
    switch (e.code) {
      case 'email-already-in-use':
        errorMessage = 'Cet email est déjà utilisé';
        break;
      case 'weak-password':
        errorMessage = 'Mot de passe trop faible (min. 6 caractères)';
        break;
      case 'invalid-email':
        errorMessage = 'Format d\'email invalide';
        break;
    }
    _showSnackbar('Erreur', errorMessage, Colors.red);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EEFA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset('assets/logo.png', height: 100),
                const SizedBox(height: 40),
                const Text(
                  'Créez un compte',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                _buildNameField(),
                const SizedBox(height: 20),
                _buildEmailField(),
                const SizedBox(height: 20),
                _buildPasswordField(),
                const SizedBox(height: 20),
                _buildRoleDropdown(),
                const SizedBox(height: 20),
                _buildSubmitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: 'Nom',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: const Icon(Icons.person),
      ),
      validator: (value) => value!.isEmpty ? 'Le nom est obligatoire.' : null,
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: 'Adresse e-mail',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: const Icon(Icons.email),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'L\'email est obligatoire.';
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
          return 'Entrez un email valide.';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Mot de passe',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (value) => value!.length < 6 ? 'Minimum 6 caractères requis' : null,
    );
  }

  Widget _buildRoleDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedRole,
      items: ['joueur', 'club', 'recruteur', 'fan']
          .map((role) => DropdownMenuItem<String>(
                value: role,
                child: Text(role.capitalizeFirst!),
              ))
          .toList(),
      onChanged: (value) => setState(() => _selectedRole = value!),
      decoration: InputDecoration(
        labelText: 'Sélectionnez un rôle',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return _isLoading
        ? const CircularProgressIndicator()
        : ElevatedButton(
            onPressed: _signUp,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: const Color(0xFF214D4F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'S\'inscrire',
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
          );
  }
}