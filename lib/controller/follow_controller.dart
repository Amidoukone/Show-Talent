import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/user_controller.dart';

class FollowController extends GetxController {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  /// Suivre un utilisateur (abonnement)
  /// - Mise à jour locale immédiate (optimiste)
  /// - Firestore en tâche de fond
  /// - Rollback automatique si erreur
  Future<bool> followUser(String currentUserId, String targetUserId) async {
    final userCtrl = Get.find<UserController>();
    final user = userCtrl.user;

    // Sécurité
    if (user == null || user.uid != currentUserId) return false;
    if (currentUserId == targetUserId) return false;

    // 🔄 Optimiste : mise à jour immédiate locale
    if (!user.followingsList.contains(targetUserId)) {
      user.followingsList.add(targetUserId);
      user.followings++;
      userCtrl.update(); // UI immédiate
    }

    try {
      // ✅ Mise à jour Firestore en tâche de fond
      await firestore.collection('users').doc(currentUserId).update({
        'followingsList': FieldValue.arrayUnion([targetUserId]),
      });

      await firestore.collection('users').doc(targetUserId).update({
        'followersList': FieldValue.arrayUnion([currentUserId]),
      });

      return true;
    } catch (e) {
      debugPrint('❌ followUser error: $e');

      // ↩️ Rollback en cas d’erreur
      user.followingsList.remove(targetUserId);
      user.followings--;
      userCtrl.update();

      return false;
    }
  }

  /// Se désabonner d’un utilisateur
  /// - Mise à jour locale immédiate (optimiste)
  /// - Firestore en tâche de fond
  /// - Rollback automatique si erreur
  Future<bool> unfollowUser(String currentUserId, String targetUserId) async {
    final userCtrl = Get.find<UserController>();
    final user = userCtrl.user;

    // Sécurité
    if (user == null || user.uid != currentUserId) return false;
    if (currentUserId == targetUserId) return false;

    // 🔄 Optimiste : suppression locale immédiate
    if (user.followingsList.contains(targetUserId)) {
      user.followingsList.remove(targetUserId);
      user.followings--;
      userCtrl.update();
    }

    try {
      // ✅ Firestore
      await firestore.collection('users').doc(currentUserId).update({
        'followingsList': FieldValue.arrayRemove([targetUserId]),
      });

      await firestore.collection('users').doc(targetUserId).update({
        'followersList': FieldValue.arrayRemove([currentUserId]),
      });

      return true;
    } catch (e) {
      debugPrint('❌ unfollowUser error: $e');

      // ↩️ Rollback
      user.followingsList.add(targetUserId);
      user.followings++;
      userCtrl.update();

      return false;
    }
  }

  /// Récupère la liste des utilisateurs abonnés ou suivis
  /// - [uid] : utilisateur cible
  /// - [listType] : 'followers' ou 'followings'
  /// - Renvoie une liste de maps avec isFollowing (bool)
  Future<List<Map<String, dynamic>>> fetchFollowList(
      String uid, String listType) async {
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      if (!doc.exists) return [];

      final List<String> ids = List<String>.from(
        doc.get(listType == 'followers' ? 'followersList' : 'followingsList') ?? [],
      );
      if (ids.isEmpty) return [];

      final currentUserId = Get.find<UserController>().user?.uid ?? '';
      final currentUserDoc =
          await firestore.collection('users').doc(currentUserId).get();
      final List<String> currentFollowings =
          List<String>.from(currentUserDoc.get('followingsList') ?? []);

      List<Map<String, dynamic>> result = [];

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
            'role': data['role'] ?? 'Non spécifié',
            'isFollowing': currentFollowings.contains(doc.id),
          });
        }
      }

      return result;
    } catch (e) {
      debugPrint('❌ fetchFollowList error: $e');
      return [];
    }
  }
}
