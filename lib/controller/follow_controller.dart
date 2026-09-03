import 'dart:async';

import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/services/users/follow_repository.dart';
import 'package:get/get.dart';
import 'package:adfoot/services/app_logger.dart';

class FollowController extends GetxController {
  FollowController({FollowRepository? followRepository})
    : _followRepository = followRepository ?? FollowRepository();

  final FollowRepository _followRepository;

  bool _isPermissionDenied(Object error) =>
      FollowRepository.isPermissionDenied(error);

  Future<void> _handleProtectedAccessDenied() async {
    if (!Get.isRegistered<UserController>()) {
      return;
    }

    await Get.find<UserController>().handleProtectedAccessDenied(
      fallbackTitle: 'Accès indisponible',
      fallbackMessage:
          'Votre session a été fermée pour protéger votre compte. Veuillez vous reconnecter.',
    );
  }

  void _syncLocalFollowingState({
    required UserController userCtrl,
    required String targetUserId,
    required bool shouldFollow,
    int? resolvedFollowingsCount,
  }) {
    final user = userCtrl.user;
    if (user == null) {
      return;
    }

    final previousFollowings = List<String>.from(user.followingsList);
    final normalizedFollowings = <String>[];
    final seen = <String>{};
    for (final id in user.followingsList) {
      final normalized = id.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      normalizedFollowings.add(normalized);
    }
    user.followingsList = normalizedFollowings;

    var changed = previousFollowings.length != user.followingsList.length;
    if (shouldFollow) {
      if (!user.followingsList.contains(targetUserId)) {
        user.followingsList.add(targetUserId);
        changed = true;
      }
    } else {
      final previousLength = user.followingsList.length;
      user.followingsList.removeWhere((id) => id == targetUserId);
      changed = user.followingsList.length != previousLength || changed;
    }

    final nextCount =
        resolvedFollowingsCount ?? user.followingsList.toSet().length;
    if (user.followings != nextCount) {
      user.followings = nextCount;
      changed = true;
    }

    if (changed) {
      userCtrl.update();
    }
  }

  Future<bool> followUser(String currentUserId, String targetUserId) async {
    final userCtrl = Get.find<UserController>();
    final user = userCtrl.user;

    if (user == null || user.uid != currentUserId) return false;
    if (currentUserId == targetUserId) return false;

    _syncLocalFollowingState(
      userCtrl: userCtrl,
      targetUserId: targetUserId,
      shouldFollow: true,
    );

    try {
      final result = await _followRepository.followUser(targetUserId);
      if (result.success) {
        _syncLocalFollowingState(
          userCtrl: userCtrl,
          targetUserId: targetUserId,
          shouldFollow: result.following ?? true,
          resolvedFollowingsCount: result.followings,
        );
      } else {
        _syncLocalFollowingState(
          userCtrl: userCtrl,
          targetUserId: targetUserId,
          shouldFollow: false,
        );
      }
      return result.success;
    } catch (error, st) {
      AppLogger.warning(
        'followUser error: $error',
        source: 'FollowController.followUser',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }

      _syncLocalFollowingState(
        userCtrl: userCtrl,
        targetUserId: targetUserId,
        shouldFollow: false,
      );
      return false;
    }
  }

  Future<bool> unfollowUser(String currentUserId, String targetUserId) async {
    final userCtrl = Get.find<UserController>();
    final user = userCtrl.user;

    if (user == null || user.uid != currentUserId) return false;
    if (currentUserId == targetUserId) return false;

    _syncLocalFollowingState(
      userCtrl: userCtrl,
      targetUserId: targetUserId,
      shouldFollow: false,
    );

    try {
      final result = await _followRepository.unfollowUser(targetUserId);
      if (result.success) {
        _syncLocalFollowingState(
          userCtrl: userCtrl,
          targetUserId: targetUserId,
          shouldFollow: result.following ?? false,
          resolvedFollowingsCount: result.followings,
        );
      } else {
        _syncLocalFollowingState(
          userCtrl: userCtrl,
          targetUserId: targetUserId,
          shouldFollow: true,
        );
      }
      return result.success;
    } catch (error, st) {
      AppLogger.warning(
        'unfollowUser error: $error',
        source: 'FollowController.unfollowUser',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }

      _syncLocalFollowingState(
        userCtrl: userCtrl,
        targetUserId: targetUserId,
        shouldFollow: true,
      );
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchFollowList(
    String uid,
    String listType,
  ) async {
    try {
      final currentFollowings =
          Get.find<UserController>().user?.followingsList
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet() ??
          <String>{};

      return _followRepository.fetchFollowList(
        uid: uid,
        listType: listType,
        currentFollowings: currentFollowings,
      );
    } catch (error, st) {
      AppLogger.warning(
        'fetchFollowList error: $error',
        source: 'FollowController.fetchFollowList',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
      return [];
    }
  }
}
