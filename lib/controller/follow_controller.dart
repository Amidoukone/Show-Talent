import 'dart:async';

import 'package:adfoot/config/app_environment.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/services/callable_auth_guard.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FollowMutationResult {
  const FollowMutationResult({
    required this.success,
    this.following,
    this.followers,
    this.followings,
  });

  final bool success;
  final bool? following;
  final int? followers;
  final int? followings;

  factory FollowMutationResult.fromActionResponse(ActionResponse response) {
    final data = response.data ?? const <String, dynamic>{};

    return FollowMutationResult(
      success: response.success,
      following: data['following'] as bool?,
      followers: (data['followers'] as num?)?.toInt(),
      followings: (data['followings'] as num?)?.toInt(),
    );
  }
}

class FollowController extends GetxController {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: AppEnvironmentConfig.functionsRegion,
  );

  bool _isPermissionDenied(Object error) =>
      (error is FirebaseException && error.code == 'permission-denied') ||
      (error is FirebaseFunctionsException &&
          (error.code == 'permission-denied' ||
              error.code == 'unauthenticated'));

  Future<void> _handleProtectedAccessDenied() async {
    if (!Get.isRegistered<UserController>()) {
      return;
    }

    await Get.find<UserController>().handleProtectedAccessDenied(
      fallbackTitle: 'Acces indisponible',
      fallbackMessage:
          'Votre session a ete fermee pour proteger votre compte. Veuillez vous reconnecter.',
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

  Future<FollowMutationResult> _runFollowMutation(
    String callableName,
    String targetUserId,
  ) async {
    final callable = _functions.httpsCallable(
      callableName,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
    );

    final raw = await CallableAuthGuard.callDataWithHttpFallback<
        Map<String, dynamic>>(
      callable,
      callableName,
      {'targetUserId': targetUserId},
    );

    final response = ActionResponse.fromMap(
      raw,
      toastOverride: ToastLevel.none,
    );

    return FollowMutationResult.fromActionResponse(response);
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
      final result = await _runFollowMutation('followUser', targetUserId);
      if (result.success) {
        _syncLocalFollowingState(
          userCtrl: userCtrl,
          targetUserId: targetUserId,
          shouldFollow: result.following ?? true,
          resolvedFollowingsCount: result.followings,
        );
      }
      return result.success;
    } catch (error) {
      debugPrint('followUser error: $error');
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
      final result = await _runFollowMutation('unfollowUser', targetUserId);
      if (result.success) {
        _syncLocalFollowingState(
          userCtrl: userCtrl,
          targetUserId: targetUserId,
          shouldFollow: result.following ?? false,
          resolvedFollowingsCount: result.followings,
        );
      }
      return result.success;
    } catch (error) {
      debugPrint('unfollowUser error: $error');
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
      final doc = await firestore.collection('users').doc(uid).get();
      if (!doc.exists) return [];

      final data = doc.data() ?? const <String, dynamic>{};
      final rawIds = (listType == 'followers'
              ? data['followersList']
              : data['followingsList']) as List<dynamic>? ??
          const <dynamic>[];
      final ids = <String>[];
      final seen = <String>{};

      for (final value in rawIds) {
        final normalized = value.toString().trim();
        if (normalized.isEmpty || !seen.add(normalized)) {
          continue;
        }
        ids.add(normalized);
      }

      if (ids.isEmpty) return [];

      final currentFollowings = Get.find<UserController>()
              .user
              ?.followingsList
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet() ??
          <String>{};

      final resultById = <String, Map<String, dynamic>>{};
      const int batchSize = 10;

      for (int i = 0; i < ids.length; i += batchSize) {
        final chunk = ids.sublist(i, (i + batchSize).clamp(0, ids.length));

        final querySnapshot = await firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in querySnapshot.docs) {
          final data = doc.data();
          resultById[doc.id] = {
            'uid': doc.id,
            'nom': data['nom'] ?? '',
            'photoProfil': data['photoProfil'] ?? '',
            'role': data['role'] ?? 'Non specifie',
            'isFollowing': currentFollowings.contains(doc.id),
          };
        }
      }

      return ids
          .map((id) => resultById[id])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } catch (error) {
      debugPrint('fetchFollowList error: $error');
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
      return [];
    }
  }
}
