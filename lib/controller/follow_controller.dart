import 'dart:async';

import 'package:adfoot/controller/user_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FollowController extends GetxController {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  bool _isPermissionDenied(Object error) =>
      error is FirebaseException && error.code == 'permission-denied';

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

  Future<bool> followUser(String currentUserId, String targetUserId) async {
    final userCtrl = Get.find<UserController>();
    final user = userCtrl.user;

    if (user == null || user.uid != currentUserId) return false;
    if (currentUserId == targetUserId) return false;

    if (!user.followingsList.contains(targetUserId)) {
      user.followingsList.add(targetUserId);
      user.followings++;
      userCtrl.update();
    }

    try {
      await firestore.collection('users').doc(currentUserId).update({
        'followingsList': FieldValue.arrayUnion([targetUserId]),
      });

      await firestore.collection('users').doc(targetUserId).update({
        'followersList': FieldValue.arrayUnion([currentUserId]),
      });

      return true;
    } catch (error) {
      debugPrint('followUser error: $error');
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }

      user.followingsList.remove(targetUserId);
      user.followings--;
      userCtrl.update();
      return false;
    }
  }

  Future<bool> unfollowUser(String currentUserId, String targetUserId) async {
    final userCtrl = Get.find<UserController>();
    final user = userCtrl.user;

    if (user == null || user.uid != currentUserId) return false;
    if (currentUserId == targetUserId) return false;

    if (user.followingsList.contains(targetUserId)) {
      user.followingsList.remove(targetUserId);
      user.followings--;
      userCtrl.update();
    }

    try {
      await firestore.collection('users').doc(currentUserId).update({
        'followingsList': FieldValue.arrayRemove([targetUserId]),
      });

      await firestore.collection('users').doc(targetUserId).update({
        'followersList': FieldValue.arrayRemove([currentUserId]),
      });

      return true;
    } catch (error) {
      debugPrint('unfollowUser error: $error');
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }

      user.followingsList.add(targetUserId);
      user.followings++;
      userCtrl.update();
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

      final List<String> ids = List<String>.from(
        doc.get(listType == 'followers' ? 'followersList' : 'followingsList') ??
            [],
      );
      if (ids.isEmpty) return [];

      final currentUserId = Get.find<UserController>().user?.uid ?? '';
      final currentUserDoc =
          await firestore.collection('users').doc(currentUserId).get();
      final List<String> currentFollowings =
          List<String>.from(currentUserDoc.get('followingsList') ?? []);

      final result = <Map<String, dynamic>>[];
      const int batchSize = 10;

      for (int i = 0; i < ids.length; i += batchSize) {
        final chunk = ids.sublist(i, (i + batchSize).clamp(0, ids.length));

        final querySnapshot = await firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in querySnapshot.docs) {
          final data = doc.data();
          result.add({
            'uid': doc.id,
            'nom': data['nom'] ?? '',
            'photoProfil': data['photoProfil'] ?? '',
            'role': data['role'] ?? 'Non specifie',
            'isFollowing': currentFollowings.contains(doc.id),
          });
        }
      }

      return result;
    } catch (error) {
      debugPrint('fetchFollowList error: $error');
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
      return [];
    }
  }
}
