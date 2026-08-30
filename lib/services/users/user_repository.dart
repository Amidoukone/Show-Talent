import 'dart:async';

import 'package:adfoot/models/user.dart';
import 'package:adfoot/config/app_environment.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:adfoot/services/callable_auth_guard.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum UserAccessIssue { missingProfile, adminPortalOnly, disabledAccount }

class UserAccessDecision {
  const UserAccessDecision({
    required this.exists,
    required this.issue,
    this.user,
    this.message,
    this.title,
  });

  final bool exists;
  final UserAccessIssue? issue;
  final AppUser? user;
  final String? message;
  final String? title;

  bool get isAllowed => exists && issue == null;
}

class UserSettingsSnapshot {
  const UserSettingsSnapshot({
    required this.role,
    required this.profilePublic,
    required this.allowMessages,
  });

  final String role;
  final bool profilePublic;
  final bool allowMessages;
}

class UserRepository {
  UserRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _functions =
          functions ??
          FirebaseFunctions.instanceFor(
            region: AppEnvironmentConfig.functionsRegion,
          );

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  static const String _missingProfileMessage =
      'Ce compte n’est plus disponible. Si vous pensez qu’il s’agit d’une erreur, contactez le support Adfoot.';
  static const String _adminPortalOnlyMessage =
      'Ce compte est réservé au portail d’administration Adfoot.';
  static const String _disabledFallbackMessage =
      'L’accès à ce compte a été désactivé. Contactez le support Adfoot.';
  static const String _missingProfileTitle = 'Compte indisponible';
  static const String _adminPortalOnlyTitle = 'Accès refusé';
  static const String _disabledTitle = 'Compte désactivé';

  static const Duration firestoreReadTimeout = Duration(seconds: 20);
  static const Duration firestoreWriteTimeout = Duration(seconds: 25);
  static const int _readRetryAttempts = 3;

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  DocumentReference<Map<String, dynamic>> _privateContactDoc(String uid) =>
      _usersCollection.doc(uid).collection('private').doc('contact');

  Future<Map<String, dynamic>?> _fetchPrivateContact(String uid) async {
    try {
      final doc = await _getWithRetry(_privateContactDoc(uid));
      return doc.data();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'private contact fetch warning',
        source: 'UserRepository._fetchPrivateContact',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  AppUser? _parseUserSafely(
    Map<String, dynamic> data, {
    Map<String, dynamic>? privateContact,
    String? source,
  }) {
    try {
      return AppUser.fromMap(data, privateContact: privateContact);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'user document parse error',
        source: source ?? 'UserRepository',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static Map<String, dynamic> _legacyFieldCleanupPatch() {
    return <String, dynamic>{
      'authDisabled': false,
      'authDisabledAt': FieldValue.delete(),
      'authDisabledBy': FieldValue.delete(),
      'authDisabledReason': FieldValue.delete(),
      'estBloque': FieldValue.delete(),
      'blockedAt': FieldValue.delete(),
      'blockedBy': FieldValue.delete(),
      'blockedReason': FieldValue.delete(),
      'blockMode': FieldValue.delete(),
      'blockedUntil': FieldValue.delete(),
    };
  }

  static UserAccessDecision evaluateUserData(Map<String, dynamic>? data) {
    if (data == null) {
      return const UserAccessDecision(
        exists: false,
        issue: UserAccessIssue.missingProfile,
        message: _missingProfileMessage,
        title: _missingProfileTitle,
      );
    }

    final user = AppUser.fromMap(data);
    if (isAdminPortalOnlyRole(data['role'])) {
      return UserAccessDecision(
        exists: true,
        issue: UserAccessIssue.adminPortalOnly,
        user: user,
        message: _adminPortalOnlyMessage,
        title: _adminPortalOnlyTitle,
      );
    }

    if (user.authDisabled) {
      return UserAccessDecision(
        exists: true,
        issue: UserAccessIssue.disabledAccount,
        user: user,
        message: _buildDisabledAccountMessage(user),
        title: _disabledTitle,
      );
    }

    return UserAccessDecision(exists: true, issue: null, user: user);
  }

  static AppUser buildPublicSignupUser({
    required String uid,
    required String nom,
    required String email,
    required String role,
    String? phone,
    DateTime? now,
  }) {
    throw StateError(publicSignupDisabledMessage);
  }

  /// Default ceiling on the directory listener.
  ///
  /// This stream feeds the messaging directory and the search author lookup,
  /// which are client-side filters over whatever it delivers. Unbounded, it
  /// re-reads and holds the *entire* `users` collection on every sign-in:
  /// harmless at today's scale, but it grows without limit into a per-open
  /// read bill, resident memory, and startup latency.
  ///
  /// 300 is well above the current population, so nothing is truncated today,
  /// while the cost of a single app open stays bounded no matter how large
  /// the collection gets. Documents past the cap are ordered by document id
  /// (Firestore's implicit order) — deliberately not by a field such as
  /// `nom`, because an `orderBy` would silently drop every document missing
  /// that field. Anyone outside the window is still reachable through the
  /// targeted [fetchUserById] hydration into `usersCache`.
  static const int directoryWatchLimit = 300;

  Stream<List<AppUser>> watchAllUsers({int limit = directoryWatchLimit}) {
    return _usersCollection
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => _parseUserSafely(
                  doc.data(),
                  source: 'UserRepository.watchAllUsers',
                ),
              )
              .whereType<AppUser>()
              .toList(growable: false),
        );
  }

  Stream<UserAccessDecision> watchUserAccess(String uid) {
    return _usersCollection.doc(uid).snapshots().map((doc) {
      if (!doc.exists) {
        return const UserAccessDecision(
          exists: false,
          issue: UserAccessIssue.missingProfile,
          message: _missingProfileMessage,
          title: _missingProfileTitle,
        );
      }

      return evaluateUserData(doc.data());
    });
  }

  Future<AppUser?> fetchUserById(String uid) async {
    final doc = await _getWithRetry(_usersCollection.doc(uid));
    final data = doc.data();
    if (!doc.exists || data == null) {
      return null;
    }

    final privateContact = await _fetchPrivateContact(uid);
    return _parseUserSafely(
      data,
      privateContact: privateContact,
      source: 'UserRepository.fetchUserById',
    );
  }

  Future<UserAccessDecision> fetchUserAccess(
    String uid, {
    bool waitForDocument = false,
    int attempts = 20,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    final doc = waitForDocument
        ? await _waitForUserDoc(uid, attempts: attempts, delay: delay)
        : await _getWithRetry(_usersCollection.doc(uid));

    if (doc == null || !doc.exists) {
      return const UserAccessDecision(
        exists: false,
        issue: UserAccessIssue.missingProfile,
        message: _missingProfileMessage,
        title: _missingProfileTitle,
      );
    }

    return evaluateUserData(doc.data());
  }

  Future<AppUser> upsertPublicSignupUser({
    required String uid,
    required String nom,
    required String email,
    required String role,
    String? phone,
  }) async {
    throw StateError(publicSignupDisabledMessage);
  }

  Future<AppUser?> markEmailVerifiedAndActivate(
    String uid, {
    bool updateLastLogin = false,
  }) async {
    final docRef = _usersCollection.doc(uid);
    final existing = await _getWithRetry(docRef);
    if (!existing.exists) {
      return null;
    }

    final decision = evaluateUserData(existing.data());
    final user = decision.user;
    if (user == null || decision.issue != null) {
      return user;
    }

    final updates = <String, dynamic>{};
    updates.addAll(_legacyFieldCleanupPatch());
    if (!user.emailVerified) {
      updates['emailVerified'] = true;
    }
    if (!user.estActif) {
      updates['estActif'] = true;
    }
    if (user.emailVerifiedAt == null) {
      updates['emailVerifiedAt'] = FieldValue.serverTimestamp();
    }
    if (updateLastLogin) {
      updates['dernierLogin'] = DateTime.now();
    }

    if (updates.isNotEmpty) {
      await docRef
          .set(updates, SetOptions(merge: true))
          .timeout(firestoreWriteTimeout);
    }

    final refreshed = await _getWithRetry(docRef);
    if (!refreshed.exists) {
      return null;
    }

    return AppUser.fromMap(refreshed.data()!);
  }

  Future<UserSettingsSnapshot?> fetchUserSettings(String uid) async {
    final user = await fetchUserById(uid);
    if (user == null) {
      return null;
    }

    return UserSettingsSnapshot(
      role: user.role,
      profilePublic: user.profilePublic,
      allowMessages: user.allowMessages,
    );
  }

  Future<void> updatePrivacySettings(
    String uid, {
    bool? profilePublic,
    bool? allowMessages,
  }) async {
    final patch = <String, dynamic>{};
    if (profilePublic != null) {
      patch['profilePublic'] = profilePublic;
    }
    if (allowMessages != null) {
      patch['allowMessages'] = allowMessages;
    }
    if (patch.isEmpty) {
      return;
    }

    await _usersCollection
        .doc(uid)
        .update(patch)
        .timeout(firestoreWriteTimeout);
  }

  /// Records that [uid] accepted the terms in version [version].
  ///
  /// Its own narrow write, alongside saveFcmToken and updatePrivacySettings,
  /// and never folded into a profile patch: `canUpdateOwnProfile` in
  /// firestore.rules carries the verified-profile invalidation invariant, so
  /// routing consent through it would cost a user their verified badge for
  /// having tapped "J'accepte".
  ///
  /// The timestamp is the server's. It is the only part of this record that
  /// has to hold up if the acceptance is ever questioned, and the matching
  /// rule (`canAcceptOwnTerms`) refuses any other value.
  Future<void> acceptTerms({
    required String uid,
    required String version,
  }) async {
    final normalized = version.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(version, 'version', 'must not be empty');
    }

    await _usersCollection
        .doc(uid)
        .update(<String, dynamic>{
          'acceptedTermsVersion': normalized,
          'acceptedTermsAt': FieldValue.serverTimestamp(),
        })
        .timeout(firestoreWriteTimeout);
  }

  /// How many further goes the background retry gets after the first failure.
  static const int _fcmTokenRetryAttempts = 3;

  /// Multiplied by the attempt number, so 4s, 8s, then 12s.
  static const Duration _fcmTokenRetryDelay = Duration(seconds: 4);

  /// Invalidates a retry whose token has been superseded.
  ///
  /// Static because callers construct `UserRepository()` fresh each time, so
  /// an instance field would give every call its own counter and arbitrate
  /// nothing. FCM can hand us a new token while a retry for the previous one
  /// is still sleeping, and a late success would then write the *old* token
  /// over the new one — which is precisely the dead-token state this is
  /// supposed to prevent.
  static int _fcmTokenSaveSerial = 0;

  /// Persists the device's FCM token, and keeps trying if the first go fails.
  ///
  /// This used to swallow both failures and return as though it had worked.
  /// The cost was invisible and severe: the backend kept the previous token,
  /// FCM rejected it on the next send, `pruneUnregisteredToken` deleted it,
  /// and the device then received **no notifications at all** until FCM
  /// happened to rotate the token again — which can be months. Nothing was
  /// logged, and the `try`/`catch` wrapped around this call in
  /// `NotificationService.listenTokenRefresh` was dead code, because this
  /// method could not throw.
  ///
  /// The first attempt is deliberately unchanged — one callable, one
  /// Firestore fallback, no delay. Three of this method's callers `await` it,
  /// and one of them sits in `AuthController._syncState`, on the path a
  /// sign-in waits for. Retrying inline would put up to 24 seconds of backoff
  /// in front of the session, which is exactly the class of bug this codebase
  /// has been digging itself out of. The retry therefore runs detached, and
  /// the caller returns as quickly as it always did.
  Future<void> saveFcmToken(String uid, String token) async {
    final sanitized = token.trim();
    if (uid.trim().isEmpty || sanitized.isEmpty) {
      return;
    }

    final serial = ++_fcmTokenSaveSerial;

    if (await _writeFcmToken(uid, sanitized)) {
      return;
    }

    // Not awaited, and that is the whole point — see above.
    unawaited(_retryFcmTokenSave(uid, sanitized, serial));
  }

  /// One full attempt: the callable, then the direct write. True if either won.
  Future<bool> _writeFcmToken(String uid, String token) async {
    try {
      final callable = _functions.httpsCallable('saveUserFcmToken');
      await CallableAuthGuard.call(callable, {'token': token});
      return true;
    } catch (_) {
      // FCM is non-critical. Keep a direct fallback for environments where the
      // callable has not been deployed yet, but never block login/upload.
    }

    try {
      await _usersCollection
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true))
          .timeout(firestoreWriteTimeout);
      return true;
    } catch (_) {}

    return false;
  }

  Future<void> _retryFcmTokenSave(String uid, String token, int serial) async {
    for (var attempt = 1; attempt <= _fcmTokenRetryAttempts; attempt++) {
      await Future<void>.delayed(_fcmTokenRetryDelay * attempt);

      // A newer token arrived; that call owns the field now.
      if (serial != _fcmTokenSaveSerial) {
        return;
      }

      // Signed out, or a different account signed in while we slept. Writing
      // now would either fail on the rules or attach this device's token to
      // the wrong profile.
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }

      if (await _writeFcmToken(uid, token)) {
        return;
      }
    }

    // Reported, because the user has now silently lost notifications and no
    // screen will ever tell them. `error` rather than `warning`: warnings are
    // sampled at 15% and this is a per-device capability loss, not noise.
    AppLogger.error(
      'FCM token could not be saved after '
      '${_fcmTokenRetryAttempts + 1} attempts; this device will receive no '
      'notifications until the token rotates again',
      source: 'notifications/token_save',
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getWithRetry(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    for (var attempt = 1; attempt <= _readRetryAttempts; attempt++) {
      try {
        return await ref.get().timeout(firestoreReadTimeout);
      } catch (error) {
        if (attempt >= _readRetryAttempts || !_isRetryableReadError(error)) {
          rethrow;
        }
        // A pending ID token outlives a 300ms pause; give it room rather than
        // burning all three attempts on the same missing credential.
        final isAuthPropagation =
            error is FirebaseException && error.code == 'unauthenticated';
        await Future.delayed(
          Duration(milliseconds: (isAuthPropagation ? 900 : 300) * attempt),
        );
      }
    }

    throw TimeoutException('Firestore read retry exhausted.');
  }

  static bool _isRetryableReadError(Object error) {
    if (error is TimeoutException) {
      return true;
    }
    if (error is! FirebaseException) {
      return false;
    }

    switch (error.code) {
      case 'unavailable':
      case 'deadline-exceeded':
      case 'aborted':
      case 'cancelled':
      case 'resource-exhausted':
      case 'internal':
        return true;
      // The ID token has not reached the Firestore client yet — normal for a
      // second or two after signing in, and the reliable state after clearing
      // app data. Retrying is the whole point; this allow-list previously
      // excluded it, so the very first read of a fresh session failed hard.
      case 'unauthenticated':
        return true;
      default:
        return false;
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _waitForUserDoc(
    String uid, {
    int attempts = 20,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    DocumentSnapshot<Map<String, dynamic>>? doc;
    for (int i = 0; i < attempts; i++) {
      doc = await _usersCollection.doc(uid).get().timeout(firestoreReadTimeout);
      if (doc.exists) {
        return doc;
      }
      await Future.delayed(delay);
    }

    return doc;
  }

  static String _buildDisabledAccountMessage(AppUser user) {
    final authDisabledReason = _normalizeReason(user.authDisabledReason);
    if (authDisabledReason != null) {
      return 'L’accès à ce compte a été désactivé. Motif : $authDisabledReason';
    }

    return _disabledFallbackMessage;
  }

  static String? _normalizeReason(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }
}
