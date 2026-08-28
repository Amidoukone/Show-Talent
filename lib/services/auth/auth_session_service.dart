import 'dart:async' show TimeoutException, unawaited;

import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/config/app_environment.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_diagnostics.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:adfoot/utils/auth_error_mapper.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:adfoot/services/app_logger.dart';

enum AuthSessionDestination { login, verifyEmail, main }

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
        return 'Compte incomplet ou non provisionné. Contactez l’équipe Adfoot.';
      case UserAccessIssue.adminPortalOnly:
        return 'Ce compte est réservé au portail d’administration Adfoot.';
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
  const SignUpFlowResult({required this.session, required this.emailDelivery});

  final AuthSessionSnapshot session;
  final EmailVerificationSendResult emailDelivery;
}

class AuthSessionService {
  AuthSessionService({
    FirebaseAuth? auth,
    UserRepository? userRepository,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _userRepository = userRepository ?? UserRepository(),
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(
             region: AppEnvironmentConfig.functionsRegion,
           );

  final FirebaseAuth _auth;
  final UserRepository _userRepository;
  final FirebaseFunctions _functions;
  static const Duration _verificationCallableTimeout = Duration(seconds: 8);

  /// Ceiling on the whole verified-state repair, deadline-driven.
  ///
  /// This repair is the only sanctioned way to reconcile a profile whose
  /// `emailVerified`/`estActif` still say false while Firebase Auth says the
  /// address is verified — Security Rules deliberately keep those two fields
  /// out of the owner-writable allowlist, so the client cannot write them
  /// directly. Every gate in the app and in the Cloud Functions reads the
  /// profile copy, so until it is reconciled the account cannot open and
  /// cannot upload.
  ///
  /// It used to be budgeted by attempt count instead of by clock: five tries
  /// of an 8s callable spaced 2s apart, ~48s, inside a 15s
  /// [_signInSessionResolveTimeout]. The timeout therefore won every single
  /// time. Worse, its `onTimeout` returns destination `main` with a null
  /// profile — which reads as success — so the repair was abandoned silently
  /// and re-abandoned identically on every subsequent sign-in. A production
  /// account sat unrepairable for three hours that way, showing its owner a
  /// spinner and then "Profil indisponible", while the Functions log recorded
  /// no call at all because the flow never got that far.
  ///
  /// Must stay comfortably below [_signInSessionResolveTimeout]; the guardrail
  /// test asserts the relationship rather than the numbers.
  static const Duration _verifiedSyncBudget = Duration(seconds: 9);
  static const Duration _verifiedSyncRetryDelay = Duration(milliseconds: 600);
  static const Duration _signInSessionResolveTimeout = Duration(seconds: 25);

  /// Ceiling on a single Firebase Auth network round-trip during sign-in.
  ///
  /// `signInWithEmailAndPassword`, `reload()` and `getIdToken(true)` each hit
  /// the network and none of them times out on its own. Only the session
  /// *resolution* that follows was bounded, so a stall in any of the earlier
  /// calls left the caller awaiting forever — and the login screen's `finally`,
  /// which clears the button's busy state, never ran. What the user sees is a
  /// spinner that turns for as long as they are willing to watch it, with no
  /// error and nothing to retry.
  ///
  /// Generous on purpose: a cold token refresh on a weak mobile connection is
  /// legitimately slow. The point is not to be strict, it is to guarantee the
  /// flow always ends somewhere the user can act on.
  static const Duration _authCallTimeout = Duration(seconds: 20);

  /// Ceiling on the whole pre-resolution phase of sign-in.
  ///
  /// Bounds the sequence as well as each call in it, so a chain of individually
  /// slow-but-not-timed-out round-trips cannot add up to an unbounded wait.
  static const Duration _signInHandshakeTimeout = Duration(seconds: 45);

  static const String _accessUnavailableTitle = 'Accès indisponible';
  static const String _accessUnavailableMessage =
      'Impossible de vérifier votre accès pour le moment. Réessayez dans quelques instants.';

  /// Runs a Firebase Auth call under [_authCallTimeout].
  ///
  /// A timeout is reported as an [AuthFlowException] rather than a bare
  /// [TimeoutException] because the login screen already maps that to a
  /// message the user can read and act on.
  static Future<T> _bounded<T>(
    Future<T> Function() call,
    String stage,
  ) {
    return call().timeout(
      _authCallTimeout,
      onTimeout: () => throw AuthFlowException(
        'La connexion au serveur prend trop de temps ($stage). '
        'Vérifiez votre réseau puis réessayez.',
      ),
    );
  }

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
  String? get currentUid => _auth.currentUser?.uid;
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
      final callable = _functions.httpsCallable(
        'completeEmailVerification',
        options: HttpsCallableOptions(timeout: _verificationCallableTimeout),
      );
      await callable.call(<String, dynamic>{
        'updateLastLogin': updateLastLogin,
      });
      return await _userRepository.fetchUserById(uid);
    } on FirebaseFunctionsException catch (error) {
      if (_isRetriableCallableSyncCode(error.code)) {
        if (kDebugMode) {
          AppLogger.debug(
            'AuthSessionService callable email verification sync skipped '
            '(${error.code}): ${error.message}',
          );
        }
        return null;
      }
      rethrow;
    }
  }

  /// Retries the verified-state repair until it succeeds or the budget runs out.
  ///
  /// Bounded by the clock, not by a retry count: an attempt is only started
  /// when there is time left to finish it, so the total can no longer overrun
  /// [_verifiedSyncBudget] and get cut off by the caller's timeout with the
  /// repair half-done and no record of it.
  Future<AppUser?> _retryEmailVerificationSync({
    required String uid,
    required bool updateLastLogin,
    Duration? budget,
  }) async {
    // The callable's very first check is `auth.getUser(uid).emailVerified`,
    // and it answers `failed-precondition` when that is false — a code this
    // client classifies as retriable. So on an account Firebase Auth itself
    // reports as unverified, the loop below spent its entire budget (~9s and
    // two to three invocations) on calls that could not succeed, on every
    // sign-in and every cold start of every unverified account. It also
    // filled the Functions log with `failed-precondition` errors, which is
    // exactly where a real verification failure would have been visible.
    //
    // `resolveSession` has just called `reload()`, so this flag reflects the
    // server, not a stale local copy. Skipping straight to the profile read
    // keeps every outcome the loop could produce: the account may still have
    // been repaired elsewhere (another device, an admin action), and that is
    // what the read below finds.
    if (!isCurrentUserEmailVerified) {
      return await _userRepository.fetchUserById(uid);
    }

    final deadline = DateTime.now().add(budget ?? _verifiedSyncBudget);

    while (true) {
      final syncedUser = await _completeEmailVerificationViaCallable(
        uid: uid,
        updateLastLogin: updateLastLogin,
      );

      if (syncedUser != null &&
          syncedUser.emailVerified &&
          syncedUser.estActif) {
        return syncedUser;
      }

      final remaining = deadline.difference(DateTime.now());
      // Only sleep and go round again if a further attempt could plausibly
      // complete inside what is left.
      if (remaining <= _verifiedSyncRetryDelay + _verificationCallableTimeout) {
        break;
      }
      await Future.delayed(_verifiedSyncRetryDelay);
    }

    return await _userRepository.fetchUserById(uid);
  }

  Future<AppUser?> _syncVerifiedAppUserState({
    required User verifiedUser,
    required AppUser? currentAppUser,
    required bool updateLastLogin,
  }) async {
    var appUser =
        await _completeEmailVerificationViaCallable(
          uid: verifiedUser.uid,
          updateLastLogin: updateLastLogin,
        ) ??
        currentAppUser;

    if (_isVerifiedActiveAppUser(appUser)) {
      return appUser;
    }

    try {
      appUser =
          await _userRepository.markEmailVerifiedAndActivate(
            verifiedUser.uid,
            updateLastLogin: updateLastLogin,
          ) ??
          appUser;
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }

      if (kDebugMode) {
        AppLogger.debug(
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
          )
          .then((syncedUser) {
            if (kDebugMode && syncedUser != null) {
              AppLogger.debug(
                'AuthSessionService background verification sync '
                'for ${syncedUser.uid}: '
                'emailVerified=${syncedUser.emailVerified} estActif=${syncedUser.estActif}',
              );
            }
          })
          .catchError((Object error) {
            // Reported, not just printed in debug.
            //
            // This runs precisely when Auth says the address is verified and
            // the profile still says it is not — the repair for an account
            // that reads "Inactif / Accès limité" in the admin portal, and
            // whose `estActif: false` is what gates access. Nobody awaits it
            // and nothing retries it: if it fails, the profile simply stays
            // wrong until the next sign-in happens to fix it.
            //
            // `debug` is dropped outright by AppLogger in a release build,
            // and this whole branch was additionally behind `kDebugMode`, so
            // on a tester's phone the repair could fail every time and leave
            // no trace anywhere.
            AuthDiagnostics.handled(
              'background verified-state repair failed; '
              'the profile may still read as inactive',
              stage: 'verification_sync',
              error: error,
            );
          }),
    );
  }

  /// Authenticates and brings the local [User] up to date, nothing more.
  ///
  /// Split out of [signInWithEmailAndPassword] so the whole credential
  /// exchange can carry one deadline. Returns the freshest [User] the SDK
  /// holds.
  Future<User> _signInHandshake({
    required String email,
    required String password,
  }) async {
    final userCred = await _bounded(
      () => _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      ),
      'authentification',
    );

    final user = userCred.user;
    if (user == null) {
      throw const AuthFlowException(
        'Impossible de se connecter pour le moment.',
      );
    }

    await _bounded(() => user.reload(), 'profil');
    User? refreshed = _auth.currentUser;
    if (refreshed != null) {
      await _bounded(() => refreshed!.getIdToken(true), 'jeton');
    }
    refreshed =
        await _refreshCurrentUserAfterVerification(
          attempts: 3,
          retryDelay: const Duration(seconds: 1),
        ) ??
        refreshed;
    if (refreshed == null) {
      throw const AuthFlowException('Session introuvable après connexion.');
    }

    return refreshed;
  }

  Future<AuthSessionSnapshot> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    // Every await below reaches the network, and none of them times out on its
    // own. Bounded individually *and* as a sequence: unbounded, a stall here
    // never returns to the login screen at all, so its `finally` never clears
    // the busy state and the user is left watching a spinner that cannot end.
    final User refreshed = await _signInHandshake(
      email: email,
      password: password,
    ).timeout(
      _signInHandshakeTimeout,
      onTimeout: () => throw const AuthFlowException(
        'La connexion prend trop de temps. Vérifiez votre réseau puis '
        'réessayez.',
      ),
    );

    return resolveSessionSafely(
      refreshed,
      waitForVerifiedUserDocument: true,
      syncVerifiedUserRecord: true,
      updateLastLogin: true,
      signOutOnInvalid: true,
    ).timeout(
      _signInSessionResolveTimeout,
      onTimeout: () {
        return AuthSessionSnapshot(
          destination: refreshed.emailVerified
              ? AuthSessionDestination.main
              : AuthSessionDestination.verifyEmail,
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

  /// Sends the reset link under [_authCallTimeout].
  ///
  /// Same reasoning as sign-in: this reaches the network and does not time out
  /// on its own, and the login screen's "Mot de passe oublié ?" owns a busy
  /// state cleared only in its `finally`. Unbounded, a stall left that button
  /// spinning for as long as the user was willing to watch it, with no error
  /// and nothing to retry.
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) {
    Future<void> send() {
      return _auth.sendPasswordResetEmail(
        email: email,
        actionCodeSettings:
            actionCodeSettings ?? _defaultPasswordResetActionCodeSettings,
      );
    }

    return _bounded(send, 'réinitialisation du mot de passe');
  }

  /// Applies the new password under [_authCallTimeout].
  ///
  /// Bounded for the same reason as the two calls above, and it was the one
  /// that was not: the reset screen owns a spinner it clears in a `finally`,
  /// so an unbounded await left "Valider" spinning with no error and no way
  /// to retry — on the one screen a user reaches when they are already
  /// locked out.
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) {
    Future<void> confirm() {
      return _auth.confirmPasswordReset(code: code, newPassword: newPassword);
    }

    return _bounded(confirm, 'changement du mot de passe');
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

    Future<void> send() async {
      await user.sendEmailVerification(
        actionCodeSettings ?? _defaultEmailVerificationActionCodeSettings,
      );
    }

    try {
      // Bounded for the same reason as the reset link above: the verify-email
      // screen's "Renvoyer" clears its busy state in a `finally` that an
      // unbounded await never reaches.
      await _bounded(send, 'envoi de l’e-mail de vérification');
      return EmailVerificationSendResult(
        sent: true,
        sentAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } on FirebaseAuthException catch (error) {
      return EmailVerificationSendResult(
        sent: false,
        errorMessage: error.message ?? 'Erreur d\u2019envoi.',
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
    final needsVerifiedSync =
        appUser != null &&
        refreshed.emailVerified &&
        (!appUser.emailVerified || !appUser.estActif);

    if (syncVerifiedUserRecord) {
      final verifiedUser = await _refreshVerifiedUserIdToken(refreshed);
      appUser =
          await _syncVerifiedAppUserState(
            verifiedUser: verifiedUser,
            currentAppUser: appUser,
            updateLastLogin: updateLastLogin,
          ) ??
          appUser;

      if (kDebugMode && appUser != null) {
        AppLogger.debug(
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
          AppLogger.debug(
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
          AppLogger.debug(
            'AuthSessionService transient Firebase access check skipped '
            '(${error.code}): ${error.message}',
          );
        }
        return _preserveCurrentSessionAfterTransientFailure(firebaseUser);
      }

      if (error.code != 'permission-denied') {
        rethrow;
      }

      // The user is about to be signed out and sent back to login, and until
      // now that happened without a word anywhere. A permission-denied here
      // means the rules refused a read this session is supposed to be allowed
      // — a real defect on our side, not a network hiccup, and the single
      // most likely cause of a tester reporting "l'application m'a
      // déconnecté".
      AuthDiagnostics.failure(
        'access check denied; signing the session out',
        stage: 'session_resolve',
        error: error,
      );

      if (signOutOnInvalid) {
        await signOut();
      }

      return const AuthSessionSnapshot(
        destination: AuthSessionDestination.login,
        failureTitle: _accessUnavailableTitle,
        failureMessage: _accessUnavailableMessage,
      );
    } on TimeoutException catch (error) {
      if (kDebugMode) {
        AppLogger.debug(
          'AuthSessionService timed out while checking access; '
          'preserving current session: $error',
        );
      }
      return _preserveCurrentSessionAfterTransientFailure(firebaseUser);
    }
  }

  Future<void> signOut() {
    return _auth.signOut();
  }
}
