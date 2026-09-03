import 'dart:async';

import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_diagnostics.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/auth/password_reset_flow.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:adfoot/utils/auth_error_mapper.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/services/app_logger.dart';

/// UserController
/// - Source de vérité pour l’état utilisateur et la navigation auth.
/// - Hydrate AppUser pour l’UI.
/// - Ajoute un cache réactif par UID pour les vidéos.
class UserController extends GetxController with WidgetsBindingObserver {
  static UserController instance = Get.find();

  final AuthSessionService _authSessionService = AuthSessionService();
  final UserRepository _userRepository = UserRepository();

  final Rx<AppUser?> _user = Rx<AppUser?>(null);
  AppUser? get user => _user.value;

  final Rx<List<AppUser>> _userList = Rx<List<AppUser>>([]);
  List<AppUser> get userList => _userList.value;

  final RxMap<String, AppUser> usersCache = <String, AppUser>{}.obs;

  StreamSubscription<List<AppUser>>? _usersSub;
  StreamSubscription<UserAccessDecision>? _currentUserAccessSub;
  String? _currentUserAccessUid;
  Map<String, String>? _pendingSessionNotice;
  Timer? _accessHeartbeat;
  int _routeRequestVersion = 0;

  final RxBool _isUserHydrationPending = false.obs;
  final RxBool _hasAttemptedHydration = false.obs;
  final RxString _sessionLoadMessage = ''.obs;
  Completer<void>? _hydrationInFlight;

  bool _navigating = false;
  bool _navScheduled = false;
  bool _accessRevocationInProgress = false;
  String? _queuedRoute;
  dynamic _queuedArguments;

  /// Backstop against a dead access listener — not the revocation path.
  ///
  /// Revocation actually arrives through [UserRepository.watchUserAccess], a
  /// `snapshots()` held open on `users/{uid}`: the admin disable flow writes
  /// `authDisabled`/`estActif` to Firestore *as well as* calling
  /// `auth.updateUser({disabled: true})` (functions/src/admin_account_actions.ts),
  /// so the listener sees every real revocation the moment it happens, and
  /// `evaluateUserData` turns it into a forced sign-out. Access is re-checked
  /// on top of that at every app resume, on any `permission-denied` from any
  /// stream, and on every refused protected action.
  ///
  /// At 60s this timer woke the cellular radio sixty times an hour — one Auth
  /// `reload()` round-trip plus one Firestore read each — to re-confirm what an
  /// already-open connection watches continuously. The only case this interval
  /// governs is a listener that died silently while the app stayed foregrounded
  /// without a single resume.
  static const Duration _accessHeartbeatInterval = Duration(minutes: 5);
  static const Duration _userHydrationTimeout = Duration(seconds: 22);

  bool get isUserHydrationPending => _isUserHydrationPending.value;
  String get sessionLoadMessage => _sessionLoadMessage.value;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);

    _authSessionService.idTokenChanges().listen(
      (User? firebaseUser) async {
        await _routeFromAuth(firebaseUser);
      },
      // The auth stream itself failed. Nothing re-subscribes, so from here on
      // the app stops reacting to sign-ins, sign-outs and token refreshes
      // entirely — it simply stays on whatever screen it was on. That was the
      // most invisible failure in the whole flow: no message, no navigation,
      // and `debug` writes nowhere in a release build.
      onError: (Object error) => AuthDiagnostics.failure(
        'auth state stream failed; session routing has stopped',
        stage: 'auth_stream',
        error: error,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      kickstart();
    });
  }

  void kickstart() {
    unawaited(_routeFromAuth(_authSessionService.currentUser));
  }

  Map<String, String>? consumePendingSessionNotice() {
    final notice = _pendingSessionNotice;
    _pendingSessionNotice = null;
    return notice;
  }

  Future<void> applyResolvedSessionSnapshot(
    AuthSessionSnapshot snapshot, {
    Map<String, dynamic>? routeArguments,
  }) async {
    final requestVersion = ++_routeRequestVersion;
    await _applySessionSnapshot(
      snapshot,
      requestVersion: requestVersion,
      routeArguments: routeArguments,
    );
  }

  Future<void> _routeFromAuth(User? firebaseUser) async {
    if (_accessRevocationInProgress && firebaseUser == null) {
      return;
    }

    final requestVersion = ++_routeRequestVersion;

    try {
      final snapshot = await _authSessionService
          .resolveSessionSafely(
            firebaseUser,
            waitForVerifiedUserDocument: true,
            syncVerifiedUserRecord: false,
            signOutOnInvalid: true,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              final fallbackUser =
                  firebaseUser ?? _authSessionService.currentUser;
              if (fallbackUser != null && fallbackUser.emailVerified) {
                return AuthSessionSnapshot(
                  destination: AuthSessionDestination.main,
                  firebaseUser: fallbackUser,
                );
              }

              return const AuthSessionSnapshot(
                destination: AuthSessionDestination.login,
              );
            },
          );

      await _applySessionSnapshot(snapshot, requestVersion: requestVersion);
    } on FirebaseAuthException catch (error, st) {
      if (AuthSessionService.isTransientAuthFailure(error)) {
        AppLogger.warning(
          'UserController route auth check kept current session '
          'after transient auth error (${error.code}): ${error.message}',
          source: 'UserController._routeFromAuth',
          error: error,
          stackTrace: st,
        );
        return;
      }

      if (!_isLatestRouteRequest(requestVersion)) {
        return;
      }

      // Same outcome as the last-resort branch further down — the session is
      // dropped and the user lands on login — so it has to be just as
      // visible. A non-transient FirebaseAuthException is the likeliest of
      // the three branches to fire, and it was still writing nowhere in a
      // release build: `debug` is dropped outright by _shouldSendToRemote.
      AuthDiagnostics.failure(
        'session routing rejected the auth check (${error.code}); '
        'falling back to login',
        stage: 'route_from_auth',
        error: error,
      );
      await _syncCurrentUserAccessWatch(null);
      await _stopAllUsersWatch();
      _user.value = null;
      await _safeOffAllNamed(AppRoutes.login);
    } on FirebaseException catch (error, st) {
      if (AuthSessionService.isTransientFirebaseFailure(error)) {
        AppLogger.warning(
          'UserController route auth check kept current session '
          'after transient Firebase error (${error.code}): ${error.message}',
          source: 'UserController._routeFromAuth',
          error: error,
          stackTrace: st,
        );
        return;
      }

      if (!_isLatestRouteRequest(requestVersion)) {
        return;
      }

      // Transient failures already returned above, so what reaches here is
      // almost always a rules refusal on the access check — a defect on our
      // side rather than a network hiccup — and it ejects the user exactly
      // like the branch above. It is also the single most likely cause of a
      // tester reporting "l'application m'a déconnecté".
      AuthDiagnostics.failure(
        'session routing rejected the Firestore access check (${error.code}); '
        'falling back to login',
        stage: 'route_from_auth',
        error: error,
      );
      await _syncCurrentUserAccessWatch(null);
      await _stopAllUsersWatch();
      _user.value = null;
      await _safeOffAllNamed(AppRoutes.login);
    } catch (error) {
      if (!_isLatestRouteRequest(requestVersion)) {
        return;
      }

      // Session routing fell through to its last resort: everything is
      // dropped and the user lands on login. Nothing above this caught it,
      // so this is the only place it can be seen from.
      AuthDiagnostics.failure(
        'session routing failed; falling back to login',
        stage: 'route_from_auth',
        error: error,
      );
      await _syncCurrentUserAccessWatch(null);
      await _stopAllUsersWatch();
      _user.value = null;
      await _safeOffAllNamed(AppRoutes.login);
    }
  }

  void _listenAllUsers() {
    if (_authSessionService.currentUser == null || _usersSub != null) {
      return;
    }

    _usersSub?.cancel();
    _usersSub = _userRepository.watchAllUsers().listen(
      (users) {
        final list = <AppUser>[];

        for (final user in users) {
          usersCache[user.uid] = user;

          if (_user.value?.uid == user.uid) {
            _user.value = user;
          }

          if (user.nom.trim().isNotEmpty) {
            list.add(user);
          }
        }

        _userList.value = list;
        update();
      },
      onError: (Object error) {
        _usersSub = null;

        // Nothing re-subscribes on its own. Until some other path happens to
        // call _listenAllUsers again, `usersCache` stops updating and the
        // people list is frozen — and with `debug` writing nowhere in a
        // release build, that was indistinguishable from "this app knows no
        // other users". The same shape as the access watcher, which was
        // already given a report for the same reason.
        AuthDiagnostics.handled(
          'user directory watch stopped; the cache will go stale',
          stage: 'directory_watch',
          error: error,
        );

        if (_isPermissionDenied(error)) {
          unawaited(_enforceCurrentSessionAccess());
        }
      },
    );
  }

  Future<void> _stopAllUsersWatch() async {
    await _usersSub?.cancel();
    _usersSub = null;
    _userList.value = const <AppUser>[];
  }

  /// Uids already being fetched by [getUserById], so a grid rebuilding many
  /// tiles for the same missing author issues one read instead of one per
  /// frame.
  final Set<String> _pendingCacheHydrations = <String>{};

  AppUser? getUserById(String uid) {
    final cached = usersCache[uid];
    if (cached != null) {
      return cached;
    }

    // The directory listener is capped (UserRepository.directoryWatchLimit),
    // so a uid outside that window is legitimately absent from the cache
    // rather than nonexistent. Fetch it once in the background; `usersCache`
    // is observable, so the caller repaints with the real author on the next
    // frame instead of permanently rendering a placeholder.
    unawaited(_hydrateCachedUser(uid));
    return null;
  }

  Future<void> _hydrateCachedUser(String uid) async {
    if (uid.trim().isEmpty ||
        usersCache.containsKey(uid) ||
        !_pendingCacheHydrations.add(uid)) {
      return;
    }

    try {
      final fetched = await _userRepository.fetchUserById(uid);
      if (fetched != null) {
        usersCache[fetched.uid] = fetched;
        update();
      }
    } catch (error, st) {
      AppLogger.warning(
        'UserController getUserById hydration failed: $error',
        source: 'UserController._hydrateCachedUser',
        error: error,
        stackTrace: st,
      );
    } finally {
      _pendingCacheHydrations.remove(uid);
    }
  }

  Future<void> refreshUser() async {
    final uid = _authSessionService.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final refreshedUser = await _userRepository
        .fetchUserById(uid)
        .timeout(_userHydrationTimeout);
    if (refreshedUser != null) {
      _user.value = refreshedUser;
      usersCache[refreshedUser.uid] = refreshedUser;
      _sessionLoadMessage.value = '';
      update();
    }
  }

  /// True once at least one hydration attempt has settled for this session.
  ///
  /// The UI needs this to tell "we haven't looked yet" apart from "we looked
  /// and found nothing": without it, a screen showing a spinner while
  /// `user == null` had no way to know the spinner would never end.
  bool get hasAttemptedHydration => _hasAttemptedHydration.value;

  /// Records the signed-in user's acceptance of the terms, then re-hydrates.
  ///
  /// The re-hydration is what clears the gate: MainScreen decides from
  /// `user.acceptedTermsVersion`, and that value only changes here once the
  /// server has confirmed the write. Forcing it means the screen never shows
  /// a consent it has not actually persisted.
  ///
  /// Throws on failure so the caller can keep the user on the screen and say
  /// so — silently swallowing this would present the app as accepted while
  /// nothing was recorded.
  Future<void> acceptTerms(String version) async {
    final uid = _authSessionService.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('no signed-in user to record a terms acceptance for');
    }

    await _userRepository.acceptTerms(uid: uid, version: version);
    await ensureCurrentUserHydrated(force: true);
  }

  Future<void> ensureCurrentUserHydrated({bool force = false}) async {
    final uid = _authSessionService.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _hasAttemptedHydration.value = true;
      _sessionLoadMessage.value = 'Session expirée. Reconnectez-vous.';
      return;
    }

    if (!force && _user.value?.uid == uid) {
      _hasAttemptedHydration.value = true;
      _sessionLoadMessage.value = '';
      return;
    }

    // Join the in-flight attempt instead of returning immediately. Returning
    // early made this method resolve while the profile was still unknown and
    // no message had been set, so callers (MainScreen's spinner,
    // UploadVideoController's profile pre-check) could not tell "loading"
    // from "finished with nothing" — which is how the app ended up sitting on
    // a spinner that never resolved.
    final inFlight = _hydrationInFlight;
    if (inFlight != null && !force) {
      return inFlight.future;
    }

    final completer = Completer<void>();
    _hydrationInFlight = completer;
    _isUserHydrationPending.value = true;
    _sessionLoadMessage.value = '';

    try {
      final hydrated = await _userRepository
          .fetchUserById(uid)
          .timeout(_userHydrationTimeout);
      if (hydrated == null) {
        _sessionLoadMessage.value =
            'Impossible de charger le profil. Réessayez dans quelques instants.';
        return;
      }

      _user.value = hydrated;
      usersCache[hydrated.uid] = hydrated;
      _sessionLoadMessage.value = '';
      _listenAllUsers();
      update();
    } on FirebaseException catch (error, st) {
      AppLogger.warning(
        'UserController ensureCurrentUserHydrated Firebase error: $error',
        source: 'UserController.ensureCurrentUserHydrated',
        error: error,
        stackTrace: st,
      );
      if (AuthSessionService.isTransientFirebaseFailure(error)) {
        _sessionLoadMessage.value =
            'Connexion instable. Vérifiez votre réseau puis réessayez.';
      } else if (_isPermissionDenied(error)) {
        _sessionLoadMessage.value =
            'Votre session ne permet pas de charger ce profil.';
        unawaited(_enforceCurrentSessionAccess());
      } else {
        _sessionLoadMessage.value =
            'Impossible de charger le profil. Réessayez dans quelques instants.';
      }
    } on TimeoutException catch (error, st) {
      AppLogger.warning(
        'UserController ensureCurrentUserHydrated timeout: $error',
        source: 'UserController.ensureCurrentUserHydrated',
        error: error,
        stackTrace: st,
      );
      _sessionLoadMessage.value =
          'Connexion trop lente. Vérifiez votre réseau puis réessayez.';
    } catch (error) {
      // This is the "Profil indisponible" screen the user is now looking
      // at, with a Réessayer button and no idea why.
      AuthDiagnostics.failure(
        'profile hydration failed',
        stage: 'hydrate_profile',
        error: error,
      );
      _sessionLoadMessage.value =
          'Impossible de charger le profil. Réessayez dans quelques instants.';
    } finally {
      _hasAttemptedHydration.value = true;
      // Belt and braces: every failure branch above sets a message, but if a
      // future edit ever adds one that doesn't, the UI must still be able to
      // leave the spinner. An empty message with no user is exactly the
      // dead-end state this whole method exists to avoid.
      if (_user.value == null && _sessionLoadMessage.value.isEmpty) {
        _sessionLoadMessage.value =
            'Impossible de charger le profil. Réessayez dans quelques instants.';
      }
      _isUserHydrationPending.value = false;
      _hydrationInFlight = null;
      if (!completer.isCompleted) {
        completer.complete();
      }
      update();
    }
  }

  Future<void> signOut() async {
    try {
      await _syncCurrentUserAccessWatch(null);
      await _stopAllUsersWatch();
      await _authSessionService.signOut();
      _user.value = null;
    } catch (error, st) {
      AppLogger.warning(
        'signOut error: $error',
        source: 'UserController.signOut',
        error: error,
        stackTrace: st,
      );
      AdFeedback.error(
        'Déconnexion impossible',
        'La session n’a pas pu être fermée. Réessayez dans quelques instants.',
      );
    }
  }

  Future<void> _syncCurrentUserAccessWatch(String? uid) async {
    if (_currentUserAccessUid == uid && _currentUserAccessSub != null) {
      return;
    }

    await _currentUserAccessSub?.cancel();
    _currentUserAccessSub = null;
    _currentUserAccessUid = uid;
    _stopAccessHeartbeat();

    if (uid == null || uid.isEmpty) {
      return;
    }

    _startAccessHeartbeat(uid);

    _currentUserAccessSub = _userRepository
        .watchUserAccess(uid)
        .listen(
          (decision) {
            if (decision.isAllowed || _accessRevocationInProgress) {
              return;
            }

            unawaited(_enforceCurrentSessionAccess());
          },
          onError: (error) {
            _currentUserAccessSub = null;
            // The access-revocation watcher just died, and the line above is
            // what makes this serious: nothing re-subscribes. Only a
            // permission-denied is acted on below; any other error leaves the
            // session running with no watcher at all, so an account disabled
            // later stays inside the app until it is restarted. A security
            // control that stops enforcing must never do it quietly.
            AuthDiagnostics.failure(
              'access watcher stopped; revocation is no longer enforced',
              stage: 'access_watch',
              error: error,
            );

            if (_isPermissionDenied(error)) {
              unawaited(_enforceCurrentSessionAccess());
            }
          },
          onDone: () {
            _currentUserAccessSub = null;
          },
        );
  }

  void _startAccessHeartbeat(String uid) {
    _accessHeartbeat?.cancel();
    _accessHeartbeat = Timer.periodic(_accessHeartbeatInterval, (_) {
      final currentUser = _authSessionService.currentUser;
      if (_accessRevocationInProgress ||
          currentUser == null ||
          currentUser.uid != uid) {
        return;
      }

      unawaited(_enforceCurrentSessionAccess());
    });
  }

  void _stopAccessHeartbeat() {
    _accessHeartbeat?.cancel();
    _accessHeartbeat = null;
  }

  Future<void> _handleCurrentUserAccessRevoked(
    UserAccessDecision decision,
  ) async {
    if (_accessRevocationInProgress ||
        _authSessionService.currentUser == null) {
      return;
    }

    _accessRevocationInProgress = true;
    final notice = _buildSessionNoticeFromDecision(decision);

    try {
      _user.value = null;
      _pendingSessionNotice = notice;
      await _syncCurrentUserAccessWatch(null);
      await _stopAllUsersWatch();
      await _authSessionService.signOut();
      await _safeOffAllNamed(AppRoutes.login, arguments: notice);
    } catch (error) {
      // Access was revoked and the eviction itself failed, so the user may
      // still be sitting in the app with a session that should be gone.
      AuthDiagnostics.failure(
        'forced sign-out failed after access revocation',
        stage: 'force_sign_out',
        error: error,
      );
    } finally {
      _accessRevocationInProgress = false;
    }
  }

  Future<void> _enforceCurrentSessionAccess() async {
    if (_accessRevocationInProgress) {
      return;
    }

    final firebaseUser = _authSessionService.currentUser;
    if (firebaseUser == null) {
      return;
    }

    try {
      final snapshot = await _authSessionService.resolveSessionSafely(
        firebaseUser,
        waitForVerifiedUserDocument: false,
        syncVerifiedUserRecord: false,
        signOutOnInvalid: false,
      );

      if (snapshot.destination == AuthSessionDestination.main) {
        await _syncCurrentUserAccessWatch(firebaseUser.uid);
        return;
      }

      await _handleCurrentUserAccessRevoked(
        UserAccessDecision(
          exists: snapshot.failure != UserAccessIssue.missingProfile,
          issue: snapshot.failure,
          user: snapshot.appUser,
          title: snapshot.failureTitle,
          message:
              snapshot.failureMessage ??
              snapshot.failure?.loginMessage ??
              'Votre session n’est plus autorisée.',
        ),
      );
    } on FirebaseAuthException catch (error, st) {
      if (!AuthSessionService.isDisabledAuthFailure(error)) {
        AppLogger.warning(
          'UserController enforceCurrentSessionAccess ignored auth error '
          '(${error.code}): ${error.message}',
          source: 'UserController._enforceCurrentSessionAccess',
          error: error,
          stackTrace: st,
        );
        return;
      }

      await _handleCurrentUserAccessRevoked(
        UserAccessDecision(
          exists: true,
          issue: UserAccessIssue.disabledAccount,
          title: 'Compte désactivé',
          message: AuthErrorMapper.toMessage(error),
        ),
      );
    } on FirebaseException catch (error, st) {
      if (AuthSessionService.isTransientFirebaseFailure(error)) {
        AppLogger.warning(
          'UserController enforceCurrentSessionAccess ignored transient '
          'Firebase error (${error.code}): ${error.message}',
          source: 'UserController._enforceCurrentSessionAccess',
          error: error,
          stackTrace: st,
        );
        return;
      }

      // Transient failures already returned above. What reaches here is a
      // real refusal of the access check, and the session is kept anyway —
      // so revocation is not being enforced right now and nothing says so.
      // This method is the backstop for the watcher that already reports;
      // the backstop failing in silence defeats the point of having one.
      AuthDiagnostics.handled(
        'access re-check failed; the session was kept unverified',
        stage: 'access_check',
        error: error,
      );
    } catch (error) {
      AuthDiagnostics.handled(
        'access re-check failed unexpectedly; the session was kept unverified',
        stage: 'access_check',
        error: error,
      );
    }
  }

  Future<void> handleProtectedAccessDenied({
    String fallbackTitle = 'Session fermée',
    String fallbackMessage =
        'Votre session n’est plus autorisée. Veuillez vous reconnecter.',
  }) async {
    if (_accessRevocationInProgress) {
      return;
    }

    final firebaseUser = _authSessionService.currentUser;
    if (firebaseUser == null) {
      _pendingSessionNotice = <String, String>{
        'sessionNoticeTitle': fallbackTitle,
        'sessionNoticeMessage': fallbackMessage,
      };
      await _safeOffAllNamed(AppRoutes.login, arguments: _pendingSessionNotice);
      return;
    }

    try {
      final snapshot = await _authSessionService.resolveSessionSafely(
        firebaseUser,
        waitForVerifiedUserDocument: false,
        syncVerifiedUserRecord: false,
        signOutOnInvalid: false,
      );

      if (snapshot.destination == AuthSessionDestination.main) {
        AppLogger.debug(
          'UserController protected access denied but session remains valid; '
          'keeping the user signed in.',
        );
        return;
      }

      await _handleCurrentUserAccessRevoked(
        UserAccessDecision(
          exists: snapshot.failure != UserAccessIssue.missingProfile,
          issue: snapshot.failure,
          user: snapshot.appUser,
          title: snapshot.failureTitle ?? fallbackTitle,
          message:
              snapshot.failureMessage ??
              snapshot.failure?.loginMessage ??
              fallbackMessage,
        ),
      );
    } catch (error, st) {
      AppLogger.warning(
        'UserController handleProtectedAccessDenied error: $error',
        source: 'UserController.handleProtectedAccessDenied',
        error: error,
        stackTrace: st,
      );
      await _handleCurrentUserAccessRevoked(
        UserAccessDecision(
          exists: true,
          issue: null,
          title: fallbackTitle,
          message: fallbackMessage,
        ),
      );
    }
  }

  Map<String, String> _buildSessionNoticeFromDecision(
    UserAccessDecision decision,
  ) {
    final title =
        decision.title ??
        switch (decision.issue) {
          UserAccessIssue.missingProfile => 'Compte indisponible',
          UserAccessIssue.adminPortalOnly => 'Accès refusé',
          UserAccessIssue.disabledAccount => 'Compte désactivé',
          null => 'Session fermée',
        };

    final message =
        decision.message ??
        decision.issue?.loginMessage ??
        'Votre session n’est plus autorisée.';

    return <String, String>{
      'sessionNoticeTitle': title,
      'sessionNoticeMessage': message,
    };
  }

  Map<String, String>? _buildSessionNoticeFromSnapshot(
    AuthSessionSnapshot snapshot,
  ) {
    final message = snapshot.failureMessage?.trim();
    if (message == null || message.isEmpty) {
      return null;
    }

    final title = snapshot.failureTitle?.trim();
    return <String, String>{
      'sessionNoticeTitle': (title == null || title.isEmpty)
          ? 'Information importante'
          : title,
      'sessionNoticeMessage': message,
    };
  }

  bool _isLatestRouteRequest(int requestVersion) {
    return requestVersion == _routeRequestVersion;
  }

  bool _shouldNavigateToMain({dynamic routeArguments}) {
    if (routeArguments != null) {
      return true;
    }

    final navigatorState = Get.key.currentState;
    if (navigatorState?.canPop() == true) {
      return false;
    }

    final currentRoute = Get.currentRoute;
    if (currentRoute.isEmpty) {
      return false;
    }

    return currentRoute == AppRoutes.splash ||
        currentRoute == AppRoutes.login ||
        currentRoute == AppRoutes.verifyEmail ||
        currentRoute == AppRoutes.resetPassword;
  }

  Future<void> _applySessionSnapshot(
    AuthSessionSnapshot snapshot, {
    required int requestVersion,
    Map<String, dynamic>? routeArguments,
  }) async {
    if (!_isLatestRouteRequest(requestVersion)) {
      return;
    }

    final watchUid = snapshot.destination == AuthSessionDestination.login
        ? null
        : snapshot.firebaseUser?.uid ?? _authSessionService.currentUser?.uid;
    await _syncCurrentUserAccessWatch(watchUid);
    if (!_isLatestRouteRequest(requestVersion)) {
      return;
    }

    switch (snapshot.destination) {
      case AuthSessionDestination.login:
        _user.value = null;
        await _stopAllUsersWatch();
        if (!_isLatestRouteRequest(requestVersion)) {
          return;
        }

        final notice = _buildSessionNoticeFromSnapshot(snapshot);
        if (notice != null) {
          _pendingSessionNotice = notice;
        }
        final navigationArguments = <String, dynamic>{
          ...?routeArguments,
          ...?notice,
        };
        await _safeOffAllNamed(
          AppRoutes.login,
          arguments: navigationArguments.isEmpty ? null : navigationArguments,
        );
        return;
      case AuthSessionDestination.verifyEmail:
        _user.value = null;
        await _stopAllUsersWatch();
        if (!_isLatestRouteRequest(requestVersion)) {
          return;
        }

        await _safeOffAllNamed(
          AppRoutes.verifyEmail,
          arguments: routeArguments,
        );
        return;
      case AuthSessionDestination.main:
        final fallbackUser = _user.value?.uid == watchUid ? _user.value : null;
        final resolvedUser = snapshot.appUser ?? fallbackUser;
        _user.value = resolvedUser;
        if (resolvedUser != null) {
          usersCache[resolvedUser.uid] = resolvedUser;
          _sessionLoadMessage.value = '';
        } else {
          unawaited(ensureCurrentUserHydrated());
        }
        _listenAllUsers();
        if (!_isLatestRouteRequest(requestVersion)) {
          return;
        }

        if (!_shouldNavigateToMain(routeArguments: routeArguments)) {
          return;
        }

        await _safeOffAllNamed(AppRoutes.main, arguments: routeArguments);
        return;
    }
  }

  bool _isPermissionDenied(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    unawaited(_enforceCurrentSessionAccess());
  }

  Future<void> _safeOffAllNamed(String route, {dynamic arguments}) async {
    // A password reset owns the screen until it is finished.
    //
    // This controller navigates on every `idTokenChanges` event, and one of
    // those always fires on the cold start that a tapped reset link produces.
    // It used to win that race and replace the reset screen with login or
    // main — the app "opening directly" before a password could be typed.
    //
    // The guard sits here rather than at the call sites so it also covers the
    // queued route drained in the `finally` below, which is how the losing
    // navigation usually arrived: scheduled while another one was in flight,
    // and replayed after the reset screen had already mounted. State updates
    // above are untouched; only the navigation waits. A notice bound for the
    // login screen stays in `_pendingSessionNotice` and is shown when the
    // reset flow releases the screen.
    if (PasswordResetFlow.isInProgress && route != AppRoutes.resetPassword) {
      return;
    }

    if (Get.key.currentState == null) {
      if (_navScheduled) {
        return;
      }

      _navScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _navScheduled = false;
        await _safeOffAllNamed(route, arguments: arguments);
      });
      return;
    }

    if (_navigating) {
      _queuedRoute = route;
      _queuedArguments = arguments;
      return;
    }

    _navigating = true;
    try {
      final current = Get.currentRoute;
      if (current == route && arguments == null) {
        return;
      }

      // `Get.offAllNamed` hands back the *pop* future of the route it pushes:
      // it completes when the user leaves the screen they were just sent to,
      // not when the navigation lands. Awaiting it was therefore awaiting the
      // user, and the ten-second timeout was the only thing ending the wait.
      //
      // Everything downstream paid for that. `_navigating` stayed true for
      // the full ten seconds of every successful navigation, so the token
      // refresh that follows any sign-in found the flag set, queued its own
      // route instead of being dropped as redundant, and the `finally` below
      // replayed it — a second `offAllNamed(/main)` that tore down and
      // rebuilt MainScreen about ten seconds after arriving on it. To the
      // user: the profile that fails to load and comes back after a restart,
      // and offers and events that vanish. The eight callers that await this
      // method were blocked for those ten seconds too.
      //
      // And it reported the success as a failure: client_logs for
      // adfoot-production is full of `navigation timed out for route=/main`
      // written moments after a navigation that had worked perfectly.
      //
      // What the callers need is for the new route to be installed, which is
      // one frame.
      final navFuture = Get.offAllNamed(route, arguments: arguments);
      if (navFuture != null) {
        // Deliberately not awaited. Swallow the outcome so that a route
        // popped much later cannot surface an unhandled error in the zone.
        unawaited(navFuture.then((_) {}, onError: (Object _) {}));
      }

      // Bounded because this method must never again be what blocks session
      // routing: if no frame is produced, carrying on is strictly better
      // than waiting.
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );

      if (Get.currentRoute != route) {
        // Now the report means what it says: a frame has been rendered and
        // the app is not where it was sent.
        AuthDiagnostics.failure(
          'navigation did not land on route=$route; '
          'still on ${Get.currentRoute}',
          stage: 'navigate',
        );
      }
    } finally {
      _navigating = false;
      final queuedRoute = _queuedRoute;
      final queuedArguments = _queuedArguments;
      _queuedRoute = null;
      _queuedArguments = null;
      if (queuedRoute != null) {
        unawaited(_safeOffAllNamed(queuedRoute, arguments: queuedArguments));
      }
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _usersSub?.cancel();
    _currentUserAccessSub?.cancel();
    _stopAccessHeartbeat();
    super.onClose();
  }
}
