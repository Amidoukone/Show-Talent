import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

/// Centralise la traduction des erreurs FirebaseAuth en messages utilisateur.
/// Homogène pour SignUp et Login.
///
/// Traduit via le catalogue GetX (`.tr`, voir `video_ui_translations.dart`)
/// plutôt que `AppLocalizations` : appelé aussi bien depuis des écrans que
/// depuis des controllers/services sans `BuildContext`
/// (`auth_session_service.dart`, `user_controller.dart`,
/// `email_link_handler.dart`).
class AuthErrorMapper {
  static String toMessage(FirebaseAuthException e) {
    final normalizedMessage = (e.message ?? '').toUpperCase();

    if (normalizedMessage.contains('CONFIGURATION_NOT_FOUND')) {
      return 'authErrorConfigurationMissing'.tr;
    }

    switch (e.code) {
      case 'email-already-in-use':
        return 'authErrorEmailAlreadyInUse'.tr;
      case 'weak-password':
        return 'authErrorWeakPassword'.tr;
      case 'invalid-email':
        return 'authErrorInvalidEmail'.tr;
      case 'operation-not-allowed':
        return 'authErrorSignupDisabled'.tr;
      case 'user-not-found':
        return 'authErrorUserNotFound'.tr;
      case 'wrong-password':
        return 'authErrorWrongPassword'.tr;
      case 'invalid-credential':
        return 'authErrorInvalidCredential'.tr;
      case 'user-disabled':
        return 'authErrorUserDisabled'.tr;
      case 'too-many-requests':
        return 'authErrorTooManyRequests'.tr;
      case 'network-request-failed':
        return 'authErrorNetworkFailed'.tr;
      case 'internal-error':
        return 'authErrorInternalError'.tr;
      default:
        return e.message ?? 'authErrorGeneric'.tr;
    }
  }
}
