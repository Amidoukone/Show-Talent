import 'package:firebase_auth/firebase_auth.dart';

/// Centralise la traduction des erreurs FirebaseAuth en messages utilisateur.
/// Homogene pour SignUp et Login.
class AuthErrorMapper {
  static String toMessage(FirebaseAuthException e) {
    final normalizedMessage = (e.message ?? '').toUpperCase();

    if (normalizedMessage.contains('CONFIGURATION_NOT_FOUND')) {
      return 'La configuration Firebase Authentication de cet environnement est incomplete. Verifiez Authentication, le provider Email/Password et la configuration du projet Firebase cible.';
    }

    switch (e.code) {
      case 'email-already-in-use':
        return 'Adresse e-mail deja utilisee.';
      case 'weak-password':
        return 'Mot de passe trop court (minimum 6 caracteres).';
      case 'invalid-email':
        return 'Adresse e-mail invalide.';
      case 'operation-not-allowed':
        return 'Inscription par e-mail desactivee.';
      case 'user-not-found':
        return 'Ce compte est introuvable. Il a peut-etre ete supprime ou cet e-mail est incorrect.';
      case 'wrong-password':
        return 'Mot de passe incorrect.';
      case 'invalid-credential':
        return 'Identifiants invalides. Verifiez votre e-mail et votre mot de passe.';
      case 'user-disabled':
        return 'L acces a ce compte a ete desactive. Contactez le support Adfoot.';
      case 'too-many-requests':
        return 'Trop de tentatives. Reessayez plus tard.';
      case 'network-request-failed':
        return 'Probleme de connexion reseau. Verifiez votre connexion.';
      case 'internal-error':
        return 'La plateforme Firebase a retourne une erreur interne pour cet environnement. Verifiez la configuration Authentication du projet cible.';
      default:
        return e.message ?? 'Une erreur est survenue. Reessayez.';
    }
  }
}
