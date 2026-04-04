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
class UserController extends GetxController {
  static UserController instance = Get.find();

  final AuthSessionService _authSessionService = AuthSessionService();
  final UserRepository _userRepository = UserRepository();

  final Rx<AppUser?> _user = Rx<AppUser?>(null);
  AppUser? get user => _user.value;

  final Rx<List<AppUser>> _userList = Rx<List<AppUser>>([]);
  List<AppUser> get userList => _userList.value;

  final RxMap<String, AppUser> usersCache = <String, AppUser>{}.obs;

  StreamSubscription<List<AppUser>>? _usersSub;

  bool _navigating = false;
  bool _navScheduled = false;

  @override
  void onInit() {
    super.onInit();

    _authSessionService.idTokenChanges().listen(
      (User? firebaseUser) async {
        await _routeFromAuth(firebaseUser);
      },
      onError: (error) =>
          debugPrint('UserController idTokenChanges error: $error'),
    );

    _listenAllUsers();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      kickstart();
    });
  }

  void kickstart() {
    _routeFromAuth(_authSessionService.currentUser);
  }

  Future<void> _routeFromAuth(User? firebaseUser) async {
    try {
      final snapshot = await _authSessionService.resolveSession(
        firebaseUser,
        waitForVerifiedUserDocument: true,
        syncVerifiedUserRecord: false,
        signOutOnInvalid: true,
      );

      _user.value = snapshot.appUser;
      if (snapshot.appUser != null) {
        usersCache[snapshot.appUser!.uid] = snapshot.appUser!;
      }

      switch (snapshot.destination) {
        case AuthSessionDestination.login:
          await _safeOffAllNamed(AppRoutes.login);
          return;
        case AuthSessionDestination.verifyEmail:
          await _safeOffAllNamed(AppRoutes.verifyEmail);
          return;
        case AuthSessionDestination.main:
          await _safeOffAllNamed(AppRoutes.main);
          return;
      }
    } catch (error) {
      debugPrint('UserController _routeFromAuth error: $error');
      _user.value = null;
      await _safeOffAllNamed(AppRoutes.login);
    }
  }

  Future<void> _listenAllUsers() async {
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
      onError: (error) => debugPrint('Erreur fetch users : $error'),
    );
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
      return;
    }

    _navigating = true;
    try {
      final current = Get.currentRoute;
      if (current == route) {
        return;
      }

      await Get.offAllNamed(route, arguments: arguments);
    } finally {
      _navigating = false;
    }
  }

  @override
  void onClose() {
    _usersSub?.cancel();
    super.onClose();
  }
}
