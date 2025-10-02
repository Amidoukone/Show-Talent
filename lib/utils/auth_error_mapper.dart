// lib/utils/auth_error_mapper.dart
import 'package:firebase_auth/firebase_auth.dart';

/// Centralise la traduction des erreurs FirebaseAuth en messages utilisateur.
/// Homogène pour SignUp & Login.
class AuthErrorMapper {
  static String toMessage(FirebaseAuthException e) {
    switch (e.code) {
      // Inscription
      case 'email-already-in-use':
        return 'Adresse e-mail déjà utilisée.';
      case 'weak-password':
        return 'Mot de passe trop court (minimum 6 caractères).';
      case 'invalid-email':
        return 'Adresse e-mail invalide.';
      case 'operation-not-allowed':
        return 'Inscription par e-mail désactivée.';

      // Connexion
      case 'user-not-found':
        return 'Aucun compte associé à cet e-mail.';
      case 'wrong-password':
        return 'Mot de passe incorrect.';
      case 'user-disabled':
        return 'Ce compte a été désactivé.';

      // Généraux
      case 'too-many-requests':
        return 'Trop de tentatives. Réessayez plus tard.';
      case 'network-request-failed':
        return 'Problème de connexion réseau. Vérifiez votre connexion.';

      default:
        return e.message ?? 'Une erreur est survenue. Réessayez.';
    }
  }
}
