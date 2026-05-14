import 'dart:async' show unawaited;

import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/config/app_environment.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:adfoot/utils/auth_error_mapper.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
      case UserAccessIssue.disabledAccount:
        return 'Ce compte a été désactivé. Contactez l’équipe Adfoot.';
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
    FirebaseFunctions? functions,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _userRepository = userRepository ?? UserRepository(),
        _functions = functions ??
            FirebaseFunctions.instanceFor(
              region: AppEnvironmentConfig.functionsRegion,
            );

  final FirebaseAuth _auth;
  final UserRepository _userRepository;
  final FirebaseFunctions _functions;
  static const Duration _verificationCallableTimeout = Duration(seconds: 8);
  static const Duration _signInSessionResolveTimeout = Duration(seconds: 15);
  static const String _accessUnavailableTitle = 'Accès indisponible';
  static const String _accessUnavailableMessage =
      'Impossible de vérifier votre accès pour le moment. Réessayez dans quelques instants.';

  static bool isDisabledAuthFailure(FirebaseAuthException error) {
    return error.code == 'user-disabled';
  }

  static bool isTransientAuthFailure(FirebaseAuthException error) {
    switch (error.code) {
      case 'network-request-failed':
      case 'too-many-requests':
      case 'internal-error':
      case 'unavailable':
      case 'deadline-exceeded':
      case 'aborted':
      case 'cancelled':
        return true;
    }

    return _messageLooksTransient(error.message);
  }

  static bool isTransientFirebaseFailure(FirebaseException error) {
    if (error is FirebaseAuthException) {
      return isTransientAuthFailure(error);
    }

    switch (error.code) {
      case 'unavailable':
      case 'deadline-exceeded':
      case 'aborted':
      case 'cancelled':
      case 'resource-exhausted':
      case 'internal':
        return true;
    }

    return _messageLooksTransient(error.message);
  }

  static bool _messageLooksTransient(String? message) {
    final normalized = message?.toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return false;
    }

    return normalized.contains('i/o error') ||
        normalized.contains('software caused connection abort') ||
        normalized.contains('connection abort') ||
        normalized.contains('socket') ||
        normalized.contains('network') ||
        normalized.contains('timed out') ||
        normalized.contains('timeout');
  }

  User? get currentUser => _auth.currentUser;
  String? get currentUserEmail => _auth.currentUser?.email;
  bool get isCurrentUserEmailVerified =>
      _auth.currentUser?.emailVerified == true;

  Stream<User?> idTokenChanges() => _auth.idTokenChanges();

  ActionCodeSettings? get _defaultEmailVerificationActionCodeSettings =>
      AppEnvironmentConfig.buildEmailVerificationActionCodeSettings();

  ActionCodeSettings? get _defaultPasswordResetActionCodeSettings =>
      AppEnvironmentConfig.buildPasswordResetActionCodeSettings();

  AuthSessionSnapshot _preserveCurrentSessionAfterTransientFailure(
    User? firebaseUser,
  ) {
    final current = _auth.currentUser ?? firebaseUser;
    if (current == null) {
      return const AuthSessionSnapshot(
        destination: AuthSessionDestination.login,
      );
    }

    return AuthSessionSnapshot(
      destination: current.emailVerified
          ? AuthSessionDestination.main
          : AuthSessionDestination.verifyEmail,
      firebaseUser: current,
    );
  }

  Future<User?> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    await user.reload();
    return _auth.currentUser;
  }

  Future<User?> _refreshCurrentUserAfterVerification({
    int attempts = 10,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    User? refreshed = _auth.currentUser;

    for (int attempt = 0; attempt < attempts; attempt++) {
      if (refreshed == null) {
        return null;
      }

      try {
        await refreshed.getIdToken(true);
      } catch (_) {
        // Keep trying with the current session object.
      }

      await refreshed.reload();
      refreshed = _auth.currentUser ?? refreshed;

      if (refreshed.emailVerified) {
        await refreshed.getIdToken(true);
        await refreshed.reload();
        return _auth.currentUser ?? refreshed;
      }

      if (attempt < attempts - 1) {
        await Future.delayed(retryDelay);
      }
    }

    return _auth.currentUser;
  }

  Future<User> _refreshVerifiedUserIdToken(User user) async {
    await user.getIdToken(true);
    return _auth.currentUser ?? user;
  }

  bool _isVerifiedActiveAppUser(AppUser? user) {
    return user != null && user.emailVerified && user.estActif;
  }

  bool _isRetriableCallableSyncCode(String code) {
    switch (code) {
      case 'failed-precondition':
      case 'not-found':
      case 'unauthenticated':
      case 'unavailable':
      case 'unimplemented':
      case 'deadline-exceeded':
      case 'internal':
        return true;
      default:
        return false;
    }
  }

  Future<AppUser?> _completeEmailVerificationViaCallable({
    required String uid,
    required bool updateLastLogin,
  }) async {
    try {
      final callable = _functions.httpsCallable('completeEmailVerification',
          options: HttpsCallableOptions(timeout: _verificationCallableTimeout));
      await callable.call(<String, dynamic>{
        'updateLastLogin': updateLastLogin,
      });
      return await _userRepository.fetchUserById(uid);
    } on FirebaseFunctionsException catch (error) {
      if (_isRetriableCallableSyncCode(error.code)) {
        if (kDebugMode) {
          debugPrint(
            'AuthSessionService callable email verification sync skipped '
            '(${error.code}): ${error.message}',
          );
        }
        return null;
      }
      rethrow;
    }
  }

  Future<AppUser?> _retryEmailVerificationSync({
    required String uid,
    required bool updateLastLogin,
    int attempts = 5,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    for (int attempt = 0; attempt < attempts; attempt++) {
      final syncedUser = await _completeEmailVerificationViaCallable(
        uid: uid,
        updateLastLogin: updateLastLogin,
      );

      if (syncedUser != null &&
          syncedUser.emailVerified &&
          syncedUser.estActif) {
        return syncedUser;
      }

      if (attempt < attempts - 1) {
        await Future.delayed(retryDelay);
      }
    }

    return await _userRepository.fetchUserById(uid);
  }

  Future<AppUser?> _syncVerifiedAppUserState({
    required User verifiedUser,
    required AppUser? currentAppUser,
    required bool updateLastLogin,
  }) async {
    var appUser = await _completeEmailVerificationViaCallable(
          uid: verifiedUser.uid,
          updateLastLogin: updateLastLogin,
        ) ??
        currentAppUser;

    if (_isVerifiedActiveAppUser(appUser)) {
      return appUser;
    }

    try {
      appUser = await _userRepository.markEmailVerifiedAndActivate(
            verifiedUser.uid,
            updateLastLogin: updateLastLogin,
          ) ??
          appUser;
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }

      if (kDebugMode) {
        debugPrint(
          'AuthSessionService local verified sync denied for '
          '${verifiedUser.uid}; fallback callable retry will continue.',
        );
      }
    }

    if (_isVerifiedActiveAppUser(appUser)) {
      return appUser;
    }

    return await _retryEmailVerificationSync(
          uid: verifiedUser.uid,
          updateLastLogin: updateLastLogin,
        ) ??
        appUser;
  }

  void _syncVerifiedAppUserStateInBackground({
    required User verifiedUser,
    required AppUser? currentAppUser,
    required bool updateLastLogin,
  }) {
    unawaited(
      _syncVerifiedAppUserState(
        verifiedUser: verifiedUser,
        currentAppUser: currentAppUser,
        updateLastLogin: updateLastLogin,
      ).then((syncedUser) {
        if (kDebugMode && syncedUser != null) {
          debugPrint(
            'AuthSessionService background verification sync '
            'for ${syncedUser.uid}: '
            'emailVerified=${syncedUser.emailVerified} estActif=${syncedUser.estActif}',
          );
        }
      }).catchError((Object error) {
        if (kDebugMode) {
          debugPrint(
            'AuthSessionService background verification sync error: $error',
          );
        }
      }),
    );
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
    User? refreshed = _auth.currentUser;
    await refreshed?.getIdToken(true);
    refreshed = await _refreshCurrentUserAfterVerification(
          attempts: 3,
          retryDelay: const Duration(seconds: 1),
        ) ??
        refreshed;
    if (refreshed == null) {
      throw const AuthFlowException('Session introuvable après connexion.');
    }

    return resolveSessionSafely(
      refreshed,
      waitForVerifiedUserDocument: true,
      syncVerifiedUserRecord: true,
      updateLastLogin: true,
      signOutOnInvalid: true,
    ).timeout(
      _signInSessionResolveTimeout,
      onTimeout: () {
        if (refreshed != null && refreshed.emailVerified) {
          return AuthSessionSnapshot(
            destination: AuthSessionDestination.main,
            firebaseUser: refreshed,
          );
        }

        return AuthSessionSnapshot(
          destination: refreshed != null && !refreshed.emailVerified
              ? AuthSessionDestination.verifyEmail
              : AuthSessionDestination.login,
          firebaseUser: refreshed,
        );
      },
    );
  }

  Future<SignUpFlowResult> signUpPublicAccount({
    required String email,
    required String password,
    required String nom,
    required String role,
    String? phone,
    ActionCodeSettings? emailVerificationSettings,
  }) async {
    throw const AuthFlowException(publicSignupDisabledMessage);
  }

  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) {
    return _auth.sendPasswordResetEmail(
      email: email,
      actionCodeSettings:
          actionCodeSettings ?? _defaultPasswordResetActionCodeSettings,
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
    ActionCodeSettings? actionCodeSettings,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFlowException(
        'Utilisateur non connecté. Veuillez vous reconnecter.',
      );
    }

    try {
      await user.sendEmailVerification(
        actionCodeSettings ?? _defaultEmailVerificationActionCodeSettings,
      );
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
    await _refreshCurrentUserAfterVerification(
      attempts: 3,
      retryDelay: const Duration(milliseconds: 700),
    );
  }

  Future<AuthSessionSnapshot> finalizeCurrentVerifiedSession({
    bool updateLastLogin = true,
    bool signOutOnInvalid = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFlowException(
        'Utilisateur non connecté. Veuillez vous reconnecter.',
      );
    }

    final refreshed = await _refreshCurrentUserAfterVerification();
    if (refreshed == null) {
      throw const AuthFlowException(
        'Session expirée. Veuillez vous reconnecter.',
      );
    }

    if (!refreshed.emailVerified) {
      final syncedUser = await _retryEmailVerificationSync(
        uid: refreshed.uid,
        updateLastLogin: updateLastLogin,
      );

      if (syncedUser != null &&
          syncedUser.emailVerified &&
          syncedUser.estActif) {
        return AuthSessionSnapshot(
          destination: AuthSessionDestination.main,
          firebaseUser: refreshed,
          appUser: syncedUser,
        );
      }

      throw const AuthFlowException(
        'Votre e-mail n’est pas encore détecté comme vérifié. Après avoir cliqué sur le lien, attendez quelques secondes puis réessayez.',
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
          decision.issue == UserAccessIssue.disabledAccount) {
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

      final syncedUser = await _retryEmailVerificationSync(
        uid: refreshed.uid,
        updateLastLogin: updateLastLogin,
      );

      if (_isVerifiedActiveAppUser(syncedUser)) {
        final reloadedUser = await _refreshCurrentUserAfterVerification(
          attempts: 3,
          retryDelay: const Duration(milliseconds: 700),
        );

        return AuthSessionSnapshot(
          destination: AuthSessionDestination.main,
          firebaseUser: reloadedUser ?? refreshed,
          appUser: syncedUser,
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

    if (decision.issue == UserAccessIssue.disabledAccount &&
        refreshed.emailVerified) {
      final syncedUser = await _syncVerifiedAppUserState(
        verifiedUser: refreshed,
        currentAppUser: decision.user,
        updateLastLogin: updateLastLogin,
      );

      if (_isVerifiedActiveAppUser(syncedUser)) {
        return AuthSessionSnapshot(
          destination: AuthSessionDestination.main,
          firebaseUser: refreshed,
          appUser: syncedUser,
        );
      }
    }

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

    if (syncVerifiedUserRecord) {
      final verifiedUser = await _refreshVerifiedUserIdToken(refreshed);
      appUser = await _syncVerifiedAppUserState(
            verifiedUser: verifiedUser,
            currentAppUser: appUser,
            updateLastLogin: updateLastLogin,
          ) ??
          appUser;

      if (kDebugMode && appUser != null) {
        debugPrint(
          'AuthSessionService synced verified user state for ${appUser.uid}: '
          'emailVerified=${appUser.emailVerified} estActif=${appUser.estActif}',
        );
      }
    } else if (needsVerifiedSync) {
      _syncVerifiedAppUserStateInBackground(
        verifiedUser: refreshed,
        currentAppUser: appUser,
        updateLastLogin: updateLastLogin,
      );
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
    } on FirebaseAuthException catch (error) {
      if (isDisabledAuthFailure(error)) {
        if (signOutOnInvalid) {
          await signOut();
        }

        return AuthSessionSnapshot(
          destination: AuthSessionDestination.login,
          firebaseUser: firebaseUser,
          failure: UserAccessIssue.disabledAccount,
          failureTitle: 'Compte désactivé',
          failureMessage: AuthErrorMapper.toMessage(error),
        );
      }

      if (isTransientAuthFailure(error)) {
        if (kDebugMode) {
          debugPrint(
            'AuthSessionService transient auth access check skipped '
            '(${error.code}): ${error.message}',
          );
        }
        return _preserveCurrentSessionAfterTransientFailure(firebaseUser);
      }

      rethrow;
    } on FirebaseException catch (error) {
      if (isTransientFirebaseFailure(error)) {
        if (kDebugMode) {
          debugPrint(
            'AuthSessionService transient Firebase access check skipped '
            '(${error.code}): ${error.message}',
          );
        }
        return _preserveCurrentSessionAfterTransientFailure(firebaseUser);
      }

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
