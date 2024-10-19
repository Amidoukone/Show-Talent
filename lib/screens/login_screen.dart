import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:show_talent/screens/home_screen.dart';
import 'package:show_talent/screens/signup_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword =
      true; // Contrôle pour masquer/afficher le mot de passe

  _login() async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      try {
        FirebaseMessaging messaging = FirebaseMessaging.instance;
        String? token = await messaging.getToken();
        if (token != null) {
          print("Token FCM: $token");

          // Assurez-vous que le token n'est pas nul avant de l'utiliser
          // Obtenir l'utilisateur actuellement connecté
          User? user = FirebaseAuth.instance.currentUser;

          if (user != null) {
            // ID de l'utilisateur
            String userId = user.uid;

            // Mettre à jour ou ajouter le token dans la collection Firestore
            await FirebaseFirestore.instance
                .collection(
                    'users') // Remplacez 'users' par votre collection Firestore
                .doc(userId) // Utiliser l'ID utilisateur comme clé du document
                .set(
                    {
                  'fcmToken': token, // Ajouter ou mettre à jour le token
                },
                    SetOptions(
                        merge:
                            true)); // Merge permet de ne pas écraser d'autres champs existants
          } else {
            print('Erreur : Utilisateur non connecté ou token FCM introuvable');
          }
        } else {
          print("Token non généré");
        }
      } catch (e) {
        print("Erreur lors de la génération du token : $e");
      }

      Get.offAll(() =>
          const HomeScreen()); // Redirection vers la page d'accueil après connexion
    } catch (e) {
      Get.snackbar('Échec de la connexion', e.toString());
    }
  }

  // Méthode pour récupérer un mot de passe oublié
  Future<void> _forgotPassword() async {
    if (_emailController.text.isEmpty) {
      Get.snackbar('Erreur',
          'Veuillez entrer votre email pour réinitialiser le mot de passe.');
      return;
    }
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _emailController.text);
      Get.snackbar('Réinitialisation du mot de passe',
          'Un email de réinitialisation vous a été envoyé.');
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EEFA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo
              Image.asset('assets/logo.png', height: 100),
              const SizedBox(height: 40),
              // Titre de la page
              const Text(
                'Connectez-vous à votre compte',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF214D4F),
                ),
              ),
              const SizedBox(height: 20),
              // Champ email
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Adresse e-mail',
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              const SizedBox(height: 20),
              // Champ mot de passe avec option afficher/masquer
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Lien pour mot de passe oublié
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgotPassword,
                  child: const Text(
                    'Mot de passe oublié ?',
                    style: TextStyle(color: Color(0xFF214D4F)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Bouton de connexion
              ElevatedButton(
                onPressed: _login,
                child: const Text(
                  'Se connecter',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              // Lien pour inscription
              TextButton(
                onPressed: () {
                  Get.to(() => const SignUpScreen());
                },
                child: const Text(
                  'Vous n\'avez pas de compte ? Inscrivez-vous',
                  style: TextStyle(color: Color(0xFF214D4F)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
