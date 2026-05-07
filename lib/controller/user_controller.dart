import 'dart:async';

import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// UserController
/// - Source de verite pour l'etat utilisateur et la navigation auth.
/// - Hydrate AppUser pour l'UI.
/// - Ajoute un cache reactif par UID pour les videos.
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

  bool _navigating = false;
  bool _navScheduled = false;
  bool _accessRevocationInProgress = false;
  String? _queuedRoute;
  dynamic _queuedArguments;

  static const Duration _accessHeartbeatInterval = Duration(seconds: 4);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);

    _authSessionService.idTokenChanges().listen(
      (User? firebaseUser) async {
        await _routeFromAuth(firebaseUser);
      },
      onError: (error) =>
          debugPrint('UserController idTokenChanges error: $error'),
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
          final fallbackUser = firebaseUser ?? _authSessionService.currentUser;
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
    } catch (error) {
      if (!_isLatestRouteRequest(requestVersion)) {
        return;
      }

      debugPrint('UserController _routeFromAuth error: $error');
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
      onError: (error) {
        debugPrint('Erreur fetch users : $error');
        _usersSub = null;

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

  AppUser? getUserById(String uid) {
    return usersCache[uid];
  }

  Future<void> refreshUser() async {
    final uid = _authSessionService.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final refreshedUser = await _userRepository.fetchUserById(uid);
    if (refreshedUser != null) {
      _user.value = refreshedUser;
      usersCache[refreshedUser.uid] = refreshedUser;
      update();
    }
  }

  Future<void> signOut() async {
    try {
      await _syncCurrentUserAccessWatch(null);
      await _stopAllUsersWatch();
      await _authSessionService.signOut();
      _user.value = null;
    } catch (error) {
      Get.snackbar(
        'Erreur',
        'Echec de deconnexion : $error',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
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

    _currentUserAccessSub = _userRepository.watchUserAccess(uid).listen(
      (decision) {
        if (decision.isAllowed || _accessRevocationInProgress) {
          return;
        }

        unawaited(_enforceCurrentSessionAccess());
      },
      onError: (error) {
        _currentUserAccessSub = null;
        debugPrint('UserController watchUserAccess error: $error');

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
      await _safeOffAllNamed(
        AppRoutes.login,
        arguments: notice,
      );
    } catch (error) {
      debugPrint('UserController forced sign-out error: $error');
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
          message: snapshot.failureMessage ??
              snapshot.failure?.loginMessage ??
              'Votre session n est plus autorisee.',
        ),
      );
    } on FirebaseAuthException catch (error) {
      await _handleCurrentUserAccessRevoked(
        UserAccessDecision(
          exists: true,
          issue: UserAccessIssue.disabledAccount,
          title: 'Compte desactive',
          message: error.message ??
              'L acces a ce compte a ete desactive. Contactez le support Adfoot.',
        ),
      );
    } catch (error) {
      debugPrint('UserController enforceCurrentSessionAccess error: $error');
    }
  }

  Future<void> handleProtectedAccessDenied({
    String fallbackTitle = 'Session fermee',
    String fallbackMessage =
        'Votre session n est plus autorisee. Veuillez vous reconnecter.',
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
      await _safeOffAllNamed(
        AppRoutes.login,
        arguments: _pendingSessionNotice,
      );
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
        await _handleCurrentUserAccessRevoked(
          UserAccessDecision(
            exists: true,
            issue: null,
            title: fallbackTitle,
            message: fallbackMessage,
          ),
        );
        return;
      }

      await _handleCurrentUserAccessRevoked(
        UserAccessDecision(
          exists: snapshot.failure != UserAccessIssue.missingProfile,
          issue: snapshot.failure,
          user: snapshot.appUser,
          title: snapshot.failureTitle ?? fallbackTitle,
          message: snapshot.failureMessage ??
              snapshot.failure?.loginMessage ??
              fallbackMessage,
        ),
      );
    } catch (error) {
      debugPrint('UserController handleProtectedAccessDenied error: $error');
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
    final title = decision.title ??
        switch (decision.issue) {
          UserAccessIssue.missingProfile => 'Compte indisponible',
          UserAccessIssue.adminPortalOnly => 'Acces refuse',
          UserAccessIssue.disabledAccount => 'Compte desactive',
          null => 'Session fermee',
        };

    final message = decision.message ??
        decision.issue?.loginMessage ??
        'Votre session n est plus autorisee.';

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
      'sessionNoticeTitle':
          (title == null || title.isEmpty) ? 'Information importante' : title,
      'sessionNoticeMessage': message,
    };
  }

  bool _isLatestRouteRequest(int requestVersion) {
    return requestVersion == _routeRequestVersion;
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
          if (routeArguments != null) ...routeArguments,
          if (notice != null) ...notice,
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
        _user.value = snapshot.appUser;
        if (snapshot.appUser != null) {
          usersCache[snapshot.appUser!.uid] = snapshot.appUser!;
        }
        _listenAllUsers();
        if (!_isLatestRouteRequest(requestVersion)) {
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

      final navFuture = Get.offAllNamed(route, arguments: arguments);
      await (navFuture ?? Future<void>.value()).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint(
            'UserController navigation timeout for route=$route',
          );
        },
      );
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
