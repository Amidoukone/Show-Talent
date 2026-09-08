import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:adfoot/config/app_environment.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:adfoot/services/callable_auth_guard.dart';
import 'package:get/get.dart';

class AccountCleanupException implements Exception {
  const AccountCleanupException({
    required this.message,
    this.requiresRecentLogin = false,
  });

  final String message;
  final bool requiresRecentLogin;

  @override
  String toString() => message;
}

/// Deletes the signed-in user's account through the `deleteOwnAccount`
/// callable.
///
/// This used to run the whole cascade client-side, and two parts of it could
/// not work from there:
///
/// * Removing the departing uid from other users' `followersList` /
///   `followingsList` means writing to documents the caller does not own,
///   which firestore.rules refuses (`allow update: if isOwner(userId)`). Every
///   such write was denied and the error swallowed, so a deleted account
///   stayed in everybody else's follow lists with their counters left too
///   high.
/// * The Firestore profile was deleted *before* `FirebaseAuth.delete()`. When
///   that last step answered `requires-recent-login`, the app told the user to
///   sign in again and retry — but the profile was already gone, so signing in
///   landed on "Ce compte n'est plus disponible" and the retry was impossible.
///
/// Both are structural, not tuning: the cascade belongs on the server, where
/// the Admin SDK is not bound by Security Rules and the ordering can be
/// enforced in one place. The callable re-checks how recently the caller
/// authenticated *before* touching anything, so a failed check now leaves the
/// account intact and genuinely retryable.
class AccountCleanupService {
  AccountCleanupService({FirebaseAuth? auth, FirebaseFunctions? functions})
    : _auth = auth ?? FirebaseAuth.instance,
      _functions =
          functions ??
          FirebaseFunctions.instanceFor(
            region: AppEnvironmentConfig.functionsRegion,
          );

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  /// Matches the callable's own ceiling. The server is the authority; this
  /// only keeps the client from making a round trip that is certain to fail.
  static const Duration _maxDeleteAuthSessionAge = Duration(minutes: 20);

  /// The cascade walks videos and their Storage objects, offers, events,
  /// conversations and follow references, so it can legitimately outlast a
  /// default callable timeout on a heavy account.
  static const Duration _callableTimeout = Duration(seconds: 300);

  static String get _reauthMessage => 'accountCleanupReauthRequiredMessage'.tr;

  /// Deletes the account and every document it owns.
  ///
  /// [deleteAuthUser] is accepted for source compatibility with the previous
  /// two-phase flow and no longer changes anything: the callable always
  /// removes the Firebase Auth user, because leaving it behind produced an
  /// account that could authenticate but had no profile to sign in with.
  Future<void> deleteAccountAndData({
    required String uid,
    bool deleteAuthUser = false,
  }) async {
    _assertCanDeleteCurrentAuthUser(uid);

    try {
      final callable = _functions.httpsCallable(
        'deleteOwnAccount',
        options: HttpsCallableOptions(timeout: _callableTimeout),
      );
      // Deliberately untyped: the response carries nothing this caller needs,
      // and a platform-channel map that refuses to cast to
      // Map<String, dynamic> would report a failure for a deletion that
      // actually succeeded — the one outcome the user must never see.
      await CallableAuthGuard.call<dynamic>(callable);
    } on FirebaseFunctionsException catch (error) {
      throw _mapCallableFailure(error);
    } catch (error, stackTrace) {
      AppLogger.debug(
        'AccountCleanup deleteOwnAccount error: $error\n$stackTrace',
      );
      throw AccountCleanupException(
        message: 'accountCleanupGenericFailedMessage'.tr,
      );
    }

    // The Auth user no longer exists server-side, so the local session is a
    // credential for nothing. Sign out here rather than leaving it to the
    // session watcher, which would otherwise surface "Ce compte n'est plus
    // disponible" over a deletion the user asked for. A failure to sign out
    // must not turn a completed deletion into an error.
    try {
      await _auth.signOut();
    } catch (error) {
      AppLogger.debug('AccountCleanup post-deletion signOut error: $error');
    }
  }

  AccountCleanupException _mapCallableFailure(
    FirebaseFunctionsException error,
  ) {
    if (_requiresRecentLogin(error)) {
      return AccountCleanupException(
        message: _reauthMessage,
        requiresRecentLogin: true,
      );
    }

    switch (error.code) {
      case 'unauthenticated':
        return AccountCleanupException(
          message: _reauthMessage,
          requiresRecentLogin: true,
        );
      case 'permission-denied':
        return AccountCleanupException(
          message: error.message ?? 'accountCleanupNotDeletableInAppMessage'.tr,
        );
      case 'deadline-exceeded':
      case 'unavailable':
        return AccountCleanupException(
          message: 'accountCleanupTimeoutMessage'.tr,
        );
      default:
        return AccountCleanupException(
          message: 'accountCleanupUnknownErrorMessage'.tr,
        );
    }
  }

  /// The callable tags the recency refusal in `details`; the message match is
  /// the fallback for a client talking to a backend deployed before that
  /// field existed.
  bool _requiresRecentLogin(FirebaseFunctionsException error) {
    if (error.code != 'failed-precondition') {
      return false;
    }

    final details = error.details;
    if (details is Map && details['reason'] == 'requires_recent_login') {
      return true;
    }

    return RegExp(
      r'v[eé]rification de s[eé]curit[eé]',
      caseSensitive: false,
    ).hasMatch(error.message ?? '');
  }

  void _assertCanDeleteCurrentAuthUser(String uid) {
    final current = _auth.currentUser;
    if (current == null || current.uid != uid) {
      throw AccountCleanupException(
        message: 'accountCleanupInvalidSessionMessage'.tr,
      );
    }

    final lastSignIn = current.metadata.lastSignInTime;
    if (lastSignIn == null) {
      throw AccountCleanupException(
        message: _reauthMessage,
        requiresRecentLogin: true,
      );
    }

    final age = DateTime.now().difference(lastSignIn);
    if (age > _maxDeleteAuthSessionAge) {
      throw AccountCleanupException(
        message: 'accountCleanupSecuritySessionExpiredMessage'.tr,
        requiresRecentLogin: true,
      );
    }
  }
}
