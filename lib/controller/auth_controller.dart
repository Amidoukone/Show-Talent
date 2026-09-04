import 'dart:async' show unawaited;

import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_diagnostics.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/email_link_handler.dart';
import 'package:adfoot/services/notifications.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:adfoot/services/web_messaging_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:adfoot/services/app_logger.dart';

/// AuthController ne navigue pas.
/// - Maintient AppUser "metier" et sa synchronisation.
/// - Gere FCM et permission systeme.
/// - La navigation reste entierement geree par UserController.
class AuthController extends GetxController {
  static AuthController instance = Get.find();

  final AuthSessionService _authSessionService = AuthSessionService();
  final UserRepository _userRepository = UserRepository();

  final Rx<User?> _firebaseUser = Rx<User?>(null);
  final Rx<AppUser?> _appUser = Rx<AppUser?>(null);

  AppUser? get user => _appUser.value;

  /// Who is signed in — read from Firebase Auth, not from the profile document.
  ///
  /// Every caller uses this to answer an *identity* question ("is this my own
  /// profile?", "am I signed in?"), never to read profile data. Sourcing it
  /// from `_appUser` conflated the two: a transient Firestore failure that
  /// left the profile unloaded also made the user stop being themselves.
  /// Concretely, the Edit button vanished from their own profile and
  /// `canViewProfile` fell through to the "profil indisponible" screen, on an
  /// account that was signed in the whole time.
  ///
  /// Firebase Auth knows the uid whether or not the profile read succeeded,
  /// and returns null the moment the user is actually signed out — which is
  /// exactly the semantics these call sites want.
  String? get currentUid => _authSessionService.currentUid;

  bool _askedNotifThisSession = false;
  int _rehydrateSerial = 0;

  @override
  void onReady() {
    super.onReady();
    _firebaseUser.bindStream(_authSessionService.idTokenChanges());
    ever<User?>(_firebaseUser, _syncState);
    _syncState(_authSessionService.currentUser);
  }

  Future<void> _syncState(User? firebaseUser) async {
    if (firebaseUser == null) {
      _appUser.value = null;
      return;
    }

    try {
      final snapshot = await _authSessionService.resolveSessionSafely(
        firebaseUser,
        waitForVerifiedUserDocument: true,
        syncVerifiedUserRecord: false,
        signOutOnInvalid: false,
      );

      _applySessionSnapshot(snapshot, firebaseUser);

      final refreshed = snapshot.firebaseUser;
      if (snapshot.destination != AuthSessionDestination.main ||
          refreshed == null) {
        return;
      }

      await _updateFcmToken(refreshed);
      await _ensureSystemNotificationPromptOnce(refreshed);
    } catch (error) {
      // Handled, not fatal: the session stands and the profile is retried
      // below. Worth a sampled record because a high rate here is what a
      // rules or connectivity problem looks like from the client.
      AuthDiagnostics.handled(
        'session sync failed; keeping the session and retrying the profile',
        stage: 'sync_state',
        error: error,
      );
      // Only the profile snapshot is unknown here — the session itself is
      // not. Access revocation has its own enforcement path (UserController's
      // access heartbeat and watchUserAccess), so discarding a profile we
      // already hold buys no safety and costs the user their identity.
      if (_appUser.value?.uid != firebaseUser.uid) {
        _appUser.value = null;
        unawaited(_rehydrateAppUser(firebaseUser.uid));
      }
    }
  }

  /// Applies a resolved session without ever downgrading a good profile.
  ///
  /// `AuthSessionService` answers a transient Firestore failure with
  /// `_preserveCurrentSessionAfterTransientFailure`: destination `main`, real
  /// `firebaseUser`, and **no** `appUser` — its way of saying "the session
  /// stands, the profile is simply unknown right now". Assigning that null
  /// straight through turned "unknown" into "gone".
  ///
  /// `destination == main` with a null `appUser` only ever comes from that
  /// path: the normal resolution always carries the document it just read.
  /// That makes it a reliable marker for "inconclusive, not empty".
  void _applySessionSnapshot(AuthSessionSnapshot snapshot, User firebaseUser) {
    if (snapshot.destination != AuthSessionDestination.main) {
      // verifyEmail / login are real decisions, not failures to look.
      _appUser.value = null;
      return;
    }

    final resolved = snapshot.appUser;
    if (resolved != null) {
      _appUser.value = resolved;
      return;
    }

    if (_appUser.value?.uid == firebaseUser.uid) {
      // Keep what we already know about this exact user.
      return;
    }

    // Nothing usable to hold on to — a cold start or a fresh install on a
    // weak network. Leaving it null here is what left the app signed in but
    // completely empty, with no way out but killing it.
    _appUser.value = null;
    unawaited(_rehydrateAppUser(firebaseUser.uid));
  }

  /// Retries the profile read that the session resolution could not complete.
  ///
  /// Bounded and serialized: a later sync supersedes an in-flight retry, so a
  /// slow network cannot stack attempts or resurrect a stale profile after
  /// sign-out.
  Future<void> _rehydrateAppUser(String uid) async {
    final serial = ++_rehydrateSerial;

    for (var attempt = 1; attempt <= _rehydrateAttempts; attempt++) {
      await Future<void>.delayed(_rehydrateDelay * attempt);

      if (serial != _rehydrateSerial) return;
      if (_authSessionService.currentUid != uid) return;
      if (_appUser.value?.uid == uid) return;

      try {
        final fetched = await _userRepository.fetchUserById(uid);
        if (serial != _rehydrateSerial ||
            _authSessionService.currentUid != uid) {
          return;
        }
        if (fetched != null) {
          _appUser.value = fetched;
          return;
        }
      } catch (error, st) {
        AppLogger.warning(
          'AuthController rehydrate attempt $attempt failed: $error',
          source: 'AuthController._rehydrateAppUser',
          error: error,
          stackTrace: st,
        );
      }
    }
  }

  static const int _rehydrateAttempts = 3;
  static const Duration _rehydrateDelay = Duration(seconds: 2);

  Future<void> signOut() async {
    // Clear what this session handled, but keep listening. Disposing here
    // cancelled the app-link subscription for the rest of the process, and
    // nothing re-initialised it — so a reset link tapped after a sign-out
    // reached a deaf app. See EmailLinkHandler.resetForNewSession.
    try {
      EmailLinkHandler.resetForNewSession();
    } catch (error, st) {
      AppLogger.warning(
        'AuthController link handler reset error: $error',
        source: 'AuthController.signOut',
        error: error,
        stackTrace: st,
      );
    }

    await _authSessionService.signOut();
    // Invalidate any retry still in flight, so a slow read cannot land a
    // profile back into a signed-out session.
    _rehydrateSerial++;
    _appUser.value = null;
    _askedNotifThisSession = false;
  }

  Future<void> _updateFcmToken(User user) async {
    try {
      final token = await WebMessagingHelper.getTokenWithRetry(retries: 2);
      if (token != null) {
        await _userRepository.saveFcmToken(user.uid, token);
      }
    } catch (error, st) {
      AppLogger.warning(
        'AuthController _updateFcmToken error: $error',
        source: 'AuthController._updateFcmToken',
        error: error,
        stackTrace: st,
      );
    }
  }

  Future<void> _ensureSystemNotificationPromptOnce(User user) async {
    if (_askedNotifThisSession) {
      return;
    }

    _askedNotifThisSession = true;
    try {
      await NotificationService.askPermissionAndUpdateToken(currentUser: user);
    } catch (error, st) {
      AppLogger.warning(
        'AuthController notifications permission error: $error',
        source: 'AuthController._ensureSystemNotificationPromptOnce',
        error: error,
        stackTrace: st,
      );
    }
  }

  /// Appel transitoire conserve pour compatibilite avec les ecrans existants.
  Future<void> handleAuthState(User? firebaseUser) => _syncState(firebaseUser);
}
