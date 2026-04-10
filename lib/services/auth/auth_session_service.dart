import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum AuthSessionDestination {
  login,
  verifyEmail,
  main,
}

extension AuthSessionDestinationRoute on AuthSessionDestination {
  String get routeName {
    switch (this) {
      case AuthSessionDestination.login:
        return AppRoutes.login;
      case AuthSessionDestination.verifyEmail:
        return AppRoutes.verifyEmail;
      case AuthSessionDestination.main:
        return AppRoutes.main;
    }
  }
}

extension AuthSessionFailureMessage on UserAccessIssue {
  String get loginMessage {
    switch (this) {
      case UserAccessIssue.missingProfile:
        return 'Compte incomplet ou non provisionne. Contactez l equipe Adfoot.';
      case UserAccessIssue.adminPortalOnly:
        return 'Ce compte est reserve au portail d administration Adfoot.';
      case UserAccessIssue.blockedOrDisabled:
        return 'Ce compte a ete suspendu, bloque ou desactive. Contactez l equipe Adfoot.';
    }
  }
}

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthSessionSnapshot {
  const AuthSessionSnapshot({
    required this.destination,
    this.firebaseUser,
    this.appUser,
    this.failure,
    this.failureMessage,
    this.failureTitle,
  });

  final AuthSessionDestination destination;
  final User? firebaseUser;
  final AppUser? appUser;
  final UserAccessIssue? failure;
  final String? failureMessage;
  final String? failureTitle;
}

class EmailVerificationSendResult {
  const EmailVerificationSendResult({
    required this.sent,
    this.sentAtMs,
    this.errorMessage,
  });

  final bool sent;
  final int? sentAtMs;
  final String? errorMessage;
}

class SignUpFlowResult {
  const SignUpFlowResult({
    required this.session,
    required this.emailDelivery,
  });

  final AuthSessionSnapshot session;
  final EmailVerificationSendResult emailDelivery;
}

class AuthSessionService {
  AuthSessionService({
    FirebaseAuth? auth,
    UserRepository? userRepository,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _userRepository = userRepository ?? UserRepository();

  final FirebaseAuth _auth;
  final UserRepository _userRepository;
  static const String _accessUnavailableTitle = 'Acces indisponible';
  static const String _accessUnavailableMessage =
      'Impossible de verifier votre acces pour le moment. Reessayez dans quelques instants.';

  User? get currentUser => _auth.currentUser;
  String? get currentUserEmail => _auth.currentUser?.email;
  bool get isCurrentUserEmailVerified =>
      _auth.currentUser?.emailVerified == true;

  Stream<User?> idTokenChanges() => _auth.idTokenChanges();

  Future<User?> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    await user.reload();
    return _auth.currentUser;
  }

  Future<AuthSessionSnapshot> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final userCred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = userCred.user;
    if (user == null) {
      throw const AuthFlowException(
        'Impossible de se connecter pour le moment.',
      );
    }

    await user.reload();
    final refreshed = _auth.currentUser;
    await refreshed?.getIdToken(true);
    if (refreshed == null) {
      throw const AuthFlowException('Session introuvable apres connexion.');
    }

    return resolveSessionSafely(
      refreshed,
      waitForVerifiedUserDocument: false,
      syncVerifiedUserRecord: false,
      signOutOnInvalid: true,
    );
  }

  Future<SignUpFlowResult> signUpPublicAccount({
    required String email,
    required String password,
    required String nom,
    required String role,
    String? phone,
    required ActionCodeSettings emailVerificationSettings,
  }) async {
    if (!isPublicSelfSignupRole(role)) {
      throw const AuthFlowException(
        'Seuls les comptes joueur et fan peuvent etre crees dans l application Adfoot.',
      );
    }

    final userCred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = userCred.user;
    if (user == null) {
      throw const AuthFlowException('Impossible de creer le compte.');
    }

    if (nom.isNotEmpty) {
      await user.updateDisplayName(nom);
    }

    final appUser = await _userRepository.upsertPublicSignupUser(
      uid: user.uid,
      nom: nom,
      email: email,
      role: role,
      phone: phone,
    );

    final emailDelivery = await sendCurrentUserEmailVerification(
      actionCodeSettings: emailVerificationSettings,
    );

    await _auth.currentUser?.reload();

    return SignUpFlowResult(
      session: AuthSessionSnapshot(
        destination: AuthSessionDestination.verifyEmail,
        firebaseUser: _auth.currentUser,
        appUser: appUser,
      ),
      emailDelivery: emailDelivery,
    );
  }

  Future<void> sendPasswordResetEmail({
    required String email,
    required ActionCodeSettings actionCodeSettings,
  }) {
    return _auth.sendPasswordResetEmail(
      email: email,
      actionCodeSettings: actionCodeSettings,
    );
  }

  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) {
    return _auth.confirmPasswordReset(
      code: code,
      newPassword: newPassword,
    );
  }

  Future<EmailVerificationSendResult> sendCurrentUserEmailVerification({
    required ActionCodeSettings actionCodeSettings,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFlowException(
        'Utilisateur non connecte. Veuillez vous reconnecter.',
      );
    }

    try {
      await user.sendEmailVerification(actionCodeSettings);
      return EmailVerificationSendResult(
        sent: true,
        sentAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } on FirebaseAuthException catch (error) {
      return EmailVerificationSendResult(
        sent: false,
        errorMessage: error.message ?? 'Erreur d envoi.',
      );
    }
  }

  Future<void> applyEmailVerificationCode(String oobCode) async {
    await _auth.checkActionCode(oobCode);
    await _auth.applyActionCode(oobCode);
    await _auth.currentUser?.reload();
  }

  Future<AuthSessionSnapshot> finalizeCurrentVerifiedSession({
    bool updateLastLogin = true,
    bool signOutOnInvalid = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFlowException(
        'Utilisateur non connecte. Veuillez vous reconnecter.',
      );
    }

    await user.reload();
    final refreshed = _auth.currentUser;
    if (refreshed == null) {
      throw const AuthFlowException(
        'Session expiree. Veuillez vous reconnecter.',
      );
    }

    if (!refreshed.emailVerified) {
      throw const AuthFlowException(
        'Votre e-mail n est pas encore detecte comme verifie. Apres avoir clique sur le lien, attendez quelques secondes puis reessayez.',
      );
    }

    return resolveSessionSafely(
      refreshed,
      waitForVerifiedUserDocument: true,
      syncVerifiedUserRecord: true,
      updateLastLogin: updateLastLogin,
      signOutOnInvalid: signOutOnInvalid,
    );
  }

  Future<AuthSessionSnapshot> resolveSession(
    User? firebaseUser, {
    bool waitForVerifiedUserDocument = true,
    bool syncVerifiedUserRecord = false,
    bool updateLastLogin = false,
    bool signOutOnInvalid = false,
  }) async {
    if (firebaseUser == null) {
      return const AuthSessionSnapshot(
        destination: AuthSessionDestination.login,
      );
    }

    await firebaseUser.reload();
    final refreshed = _auth.currentUser;
    if (refreshed == null) {
      return const AuthSessionSnapshot(
        destination: AuthSessionDestination.login,
      );
    }

    if (!refreshed.emailVerified) {
      final decision = await _userRepository.fetchUserAccess(
        refreshed.uid,
        waitForDocument: false,
      );

      if (decision.issue == UserAccessIssue.adminPortalOnly ||
          decision.issue == UserAccessIssue.blockedOrDisabled) {
        if (signOutOnInvalid) {
          await signOut();
        }

        return AuthSessionSnapshot(
          destination: AuthSessionDestination.login,
          firebaseUser: refreshed,
          appUser: decision.user,
          failure: decision.issue,
          failureMessage: decision.message,
          failureTitle: decision.title,
        );
      }

      return AuthSessionSnapshot(
        destination: AuthSessionDestination.verifyEmail,
        firebaseUser: refreshed,
        appUser: decision.user,
      );
    }

    final decision = await _userRepository.fetchUserAccess(
      refreshed.uid,
      waitForDocument: waitForVerifiedUserDocument,
    );

    if (!decision.isAllowed) {
      if (signOutOnInvalid) {
        await signOut();
      }

      return AuthSessionSnapshot(
        destination: AuthSessionDestination.login,
        firebaseUser: refreshed,
        appUser: decision.user,
        failure: decision.issue,
        failureMessage: decision.message,
        failureTitle: decision.title,
      );
    }

    var appUser = decision.user;
    final needsVerifiedSync = appUser != null &&
        refreshed.emailVerified &&
        (!appUser.emailVerified || !appUser.estActif);

    if (syncVerifiedUserRecord || needsVerifiedSync) {
      appUser = await _userRepository.markEmailVerifiedAndActivate(
            refreshed.uid,
            updateLastLogin: updateLastLogin,
          ) ??
          appUser;
    }

    return AuthSessionSnapshot(
      destination: AuthSessionDestination.main,
      firebaseUser: refreshed,
      appUser: appUser,
    );
  }

  Future<AuthSessionSnapshot> resolveSessionSafely(
    User? firebaseUser, {
    bool waitForVerifiedUserDocument = true,
    bool syncVerifiedUserRecord = false,
    bool updateLastLogin = false,
    bool signOutOnInvalid = false,
  }) async {
    try {
      return await resolveSession(
        firebaseUser,
        waitForVerifiedUserDocument: waitForVerifiedUserDocument,
        syncVerifiedUserRecord: syncVerifiedUserRecord,
        updateLastLogin: updateLastLogin,
        signOutOnInvalid: signOutOnInvalid,
      );
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }

      if (signOutOnInvalid) {
        await signOut();
      }

      return const AuthSessionSnapshot(
        destination: AuthSessionDestination.login,
        failureTitle: _accessUnavailableTitle,
        failureMessage: _accessUnavailableMessage,
      );
    }
  }

  Future<void> signOut() {
    return _auth.signOut();
  }
}
