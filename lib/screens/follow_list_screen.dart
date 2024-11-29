import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/controller/follow_controller.dart';

class FollowListScreen extends StatelessWidget {
  final String uid;
  final String listType; // 'followers' ou 'followings'

  FollowListScreen({super.key, required this.uid, required this.listType});

  final FollowController _followController = Get.find<FollowController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          listType == 'followers' ? 'Followers' : 'Followings',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchFollowList(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Une erreur est survenue. Veuillez réessayer.',
                style: const TextStyle(fontSize: 16, color: Colors.red),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text(
                listType == 'followers'
                    ? 'Aucun follower pour l’instant.'
                    : 'Aucune personne suivie pour l’instant.',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          List<Map<String, dynamic>> users = snapshot.data!;
          return ListView.builder(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            itemCount: users.length,
            itemBuilder: (context, index) {
              Map<String, dynamic> user = users[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 10.0),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user['photoProfil'] != ''
                        ? NetworkImage(user['photoProfil'])
                        : const AssetImage('assets/images/default_avatar.png') as ImageProvider,
                    backgroundColor: Colors.grey.shade200,
                  ),
                  title: Text(
                    user['nom'] ?? 'Utilisateur',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    user['role'] ?? 'Non spécifié',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  trailing: _buildFollowButton(user),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Bouton Suivre/Dessuivre
  Widget _buildFollowButton(Map<String, dynamic> user) {
    bool isFollowing = user['isFollowing'] ?? false;
    return ElevatedButton(
      onPressed: () async {
        String currentUserId = uid;
        if (isFollowing) {
          await _followController.unfollowUser(currentUserId, user['uid']);
        } else {
          await _followController.followUser(currentUserId, user['uid']);
        }
        // Mise à jour de l'interface
        Get.forceAppUpdate();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isFollowing ? Colors.red : Colors.green,
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      ),
      child: Text(
        isFollowing ? 'Dessuivre' : 'Suivre',
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }

  /// Méthode pour récupérer les followers ou followings depuis Firestore
  Future<List<Map<String, dynamic>>> _fetchFollowList() async {
    try {
      // Récupérer la liste des IDs des utilisateurs
      DocumentSnapshot userSnapshot = await _followController.firestore.collection('users').doc(uid).get();

      if (!userSnapshot.exists) return [];

      List<String> userIds = List<String>.from(
          listType == 'followers' ? userSnapshot['followersList'] : userSnapshot['followingsList']);

      if (userIds.isEmpty) return [];

      // Récupérer les informations des utilisateurs correspondants
      QuerySnapshot<Map<String, dynamic>> usersSnapshot = await _followController.firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: userIds)
          .get();

      // Identifier si l'utilisateur actuel suit déjà chaque utilisateur
      String currentUserId = uid;
      DocumentSnapshot currentUserSnapshot =
          await _followController.firestore.collection('users').doc(currentUserId).get();
      List<String> currentFollowings = List<String>.from(currentUserSnapshot['followingsList'] ?? []);

      return usersSnapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data();
        return {
          'uid': doc.id,
          'nom': data['nom'] ?? 'Utilisateur',
          'photoProfil': data['photoProfil'] ?? '',
          'role': data['role'] ?? 'Non spécifié',
          'isFollowing': currentFollowings.contains(doc.id),
        };
      }).toList();
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de chargement des données : $e');
      return [];
    }
  }
}
