import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/email_link_handler.dart';
import 'package:adfoot/services/notifications.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:adfoot/services/web_messaging_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
  String? get currentUid => _appUser.value?.uid;

  bool _askedNotifThisSession = false;

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
      final snapshot = await _authSessionService.resolveSession(
        firebaseUser,
        waitForVerifiedUserDocument: true,
        syncVerifiedUserRecord: true,
        signOutOnInvalid: true,
      );

      _appUser.value = snapshot.appUser;
      final refreshed = snapshot.firebaseUser;
      if (snapshot.destination != AuthSessionDestination.main ||
          refreshed == null) {
        return;
      }

      await _updateFcmToken(refreshed);
      await _ensureSystemNotificationPromptOnce(refreshed);
    } catch (error) {
      debugPrint('AuthController _syncState error: $error');
      _appUser.value = null;
    }
  }

  Future<void> signOut() async {
    try {
      await EmailLinkHandler.dispose();
    } catch (_) {}

    await _authSessionService.signOut();
    _appUser.value = null;
    _askedNotifThisSession = false;
  }

  Future<void> _updateFcmToken(User user) async {
    try {
      final token = await WebMessagingHelper.getTokenWithRetry(retries: 2);
      if (token != null) {
        await _userRepository.saveFcmToken(user.uid, token);
      }
    } catch (error) {
      debugPrint('AuthController _updateFcmToken error: $error');
    }
  }

  Future<void> _ensureSystemNotificationPromptOnce(User user) async {
    if (_askedNotifThisSession) {
      return;
    }

    _askedNotifThisSession = true;
    try {
      await NotificationService.askPermissionAndUpdateToken(currentUser: user);
    } catch (error) {
      debugPrint('AuthController notifications permission error: $error');
    }
  }

  /// Appel transitoire conserve pour compatibilite avec les ecrans existants.
  Future<void> handleAuthState(User? firebaseUser) => _syncState(firebaseUser);
}
