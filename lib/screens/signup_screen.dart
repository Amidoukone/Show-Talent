import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/screens/login_screen.dart';
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
  String _selectedRole = 'joueur'; // Rôle par défaut
  bool _obscurePassword = true; // Contrôle de visibilité du mot de passe
  bool _isLoading = false; // Indicateur de chargement

  final _formKey = GlobalKey<FormState>(); // Clé pour valider le formulaire

  /// Fonction pour gérer l'inscription de l'utilisateur
  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Création de l'utilisateur Firebase
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;
      if (user != null) {
        // Envoi de l'email de vérification
        await user.sendEmailVerification();

        // Création d'un nouvel utilisateur avec les informations fournies
        AppUser newUser = AppUser(
          uid: user.uid,
          nom: _nameController.text.trim(),
          email: _emailController.text.trim(),
          role: _selectedRole,
          photoProfil: '', // Le chemin de la photo sera mis à jour plus tard
          estActif: true, // Actif par défaut
          estBloque: false, // Non bloqué par défaut
          followers: 0,
          followings: 0,
          dateInscription: DateTime.now(),
          dernierLogin: DateTime.now(),
          followersList: [],
          followingsList: [],
        );

        // Sauvegarde des données utilisateur dans Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(newUser.toMap());

        // Message de succès
        Get.snackbar(
          'Inscription réussie',
          'Un email de vérification vous a été envoyé. Veuillez vérifier votre email.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );

        // Redirection vers la page de connexion
        Get.offAll(() => const LoginScreen());
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Échec de l\'inscription.';
      if (e.code == 'email-already-in-use') {
        errorMessage = 'Cet email est déjà utilisé.';
      } else if (e.code == 'weak-password') {
        errorMessage = 'Le mot de passe est trop faible.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'L\'email est invalide.';
      }

      Get.snackbar(
        'Erreur',
        errorMessage,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'Erreur',
        'Une erreur inattendue est survenue. Veuillez réessayer.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
                // Logo
                Image.asset('assets/logo.png', height: 100),
                const SizedBox(height: 40),

                // Titre de la page
                const Text(
                  'Créez un compte',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                // Champ Nom
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Nom',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    prefixIcon: const Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Le nom est obligatoire.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Champ Email
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Adresse e-mail',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    prefixIcon: const Icon(Icons.email),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'L\'email est obligatoire.';
                    }
                    if (!RegExp(
                            r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
                        .hasMatch(value)) {
                      return 'Entrez un email valide.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Champ mot de passe
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Le mot de passe est obligatoire.';
                    }
                    if (value.length < 6) {
                      return 'Le mot de passe doit contenir au moins 6 caractères.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Sélection du rôle
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  items: ['joueur', 'club', 'recruteur', 'fan']
                      .map((String role) => DropdownMenuItem<String>(
                            value: role,
                            child: Text(role),
                          ))
                      .toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedRole = newValue!;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Sélectionnez un rôle',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Bouton d'inscription
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _signUp,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'S\'inscrire',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
