import 'package:firebase_auth/firebase_auth.dart';

/// Centralise la traduction des erreurs FirebaseAuth en messages utilisateur.
/// Homogène pour SignUp et Login.
class AuthErrorMapper {
  static String toMessage(FirebaseAuthException e) {
    final normalizedMessage = (e.message ?? '').toUpperCase();

    if (normalizedMessage.contains('CONFIGURATION_NOT_FOUND')) {
      return 'La configuration Firebase Authentication de cet environnement est incomplète. Vérifiez Authentication, le provider Email/Password et la configuration du projet Firebase cible.';
    }

    switch (e.code) {
      case 'email-already-in-use':
        return 'Adresse e-mail déjà utilisée.';
      case 'weak-password':
        return 'Mot de passe trop court (minimum 6 caractères).';
      case 'invalid-email':
        return 'Adresse e-mail invalide.';
      case 'operation-not-allowed':
        return 'Inscription par e-mail désactivée.';
      case 'user-not-found':
        return 'Ce compte est introuvable. Il a peut-être été supprimé ou cet e-mail est incorrect.';
      case 'wrong-password':
        return 'Mot de passe incorrect.';
      case 'invalid-credential':
        return 'Identifiants invalides. Vérifiez votre e-mail et votre mot de passe.';
      case 'user-disabled':
        return 'L\'accès à ce compte a été désactivé. Contactez le support Adfoot.';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessayez plus tard.';
      case 'network-request-failed':
        return 'Problème de connexion réseau. Vérifiez votre connexion.';
      case 'internal-error':
        return 'La plateforme Firebase a retourné une erreur interne pour cet environnement. Vérifiez la configuration Authentication du projet cible.';
      default:
        return e.message ?? 'Une erreur est survenue. Réessayez.';
    }
  }
}
