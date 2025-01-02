import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';

class ProfileController extends GetxController {
  AppUser? user; // Modèle utilisateur
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  var isLoadingPhoto =
      false.obs; // Indique si la photo de profil est en cours de chargement
  var videoList = <Video>[].obs; // Liste des vidéos de l'utilisateur

  /// Chargement des informations utilisateur depuis Firestore
  void updateUserId(String uid) {
    _firestore.collection('users').doc(uid).get().then((snapshot) {
      if (snapshot.exists) {
        user = AppUser.fromMap(snapshot.data()!);
        fetchUserVideos(uid); // Charger les vidéos de l'utilisateur
        update();
      }
    }).catchError((e) {
      Get.snackbar('Erreur', 'Erreur lors du chargement du profil.');
    });
  }

  /// Mise à jour de la photo de profil
  Future<void> updateProfilePhoto(String uid, String photoPath) async {
    try {
      isLoadingPhoto.value = true;
      String photoUrl = await _uploadPhotoToStorage(uid, photoPath);
      await _firestore
          .collection('users')
          .doc(uid)
          .update({'photoProfil': photoUrl});
      user?.photoProfil = photoUrl;
      update();
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la mise à jour de la photo de profil.');
    } finally {
      isLoadingPhoto.value = false;
    }
  }

  /// Téléversement de la photo de profil vers Firebase Storage
  Future<String> _uploadPhotoToStorage(String uid, String filePath) async {
    final ref = _storage.ref().child('profilePhotos/$uid');
    await ref.putFile(File(filePath));
    return await ref.getDownloadURL();
  }

  /// Récupération des vidéos de l'utilisateur
  void fetchUserVideos(String uid) async {
    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('videos')
          .where('uid', isEqualTo: uid)
          .get();

      videoList.value = snapshot.docs
          .map((doc) => Video.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Get.snackbar('Erreur', 'Échec du chargement des vidéos.');
    }
  }

  /// Mise à jour des données utilisateur
  Future<void> updateUserProfile(AppUser updatedUser) async {
    try {
      // Mettre à jour dans Firestore
      await _firestore
          .collection('users')
          .doc(updatedUser.uid)
          .update(updatedUser.toMap());
      // Mettre à jour localement
      user = updatedUser;
      update();
      Get.snackbar('Succès', 'Profil mis à jour avec succès.');
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la mise à jour du profil.');
    }
  }

  /// Gestion des abonnements (Follow/Unfollow)
  Future<void> followUser() async {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (user == null || currentUserId == null || currentUserId == user!.uid) {
      return;
    }

    String profileUserId = user!.uid;

    try {
      DocumentSnapshot<Map<String, dynamic>> currentUserSnapshot =
          await _firestore.collection('users').doc(currentUserId).get();

      if (!currentUserSnapshot.exists) return;

      Map<String, dynamic> currentUserData = currentUserSnapshot.data()!;
      List<String> followings =
          List<String>.from(currentUserData['followings'] ?? []);

      if (followings.contains(profileUserId)) {
        followings.remove(profileUserId);
        user!.followers--;
      } else {
        followings.add(profileUserId);
        user!.followers++;
      }

      await _firestore
          .collection('users')
          .doc(currentUserId)
          .update({'followings': followings});
      await _firestore.collection('users').doc(profileUserId).update({
        'followers': user!.followers,
      });

      update();
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de suivre cet utilisateur.');
    }
  }

  /// Obtenir l'utilisateur actuellement connecté
  AppUser? getLoggedInUser() {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null && user?.uid == currentUserId) {
      return user;
    }
    return null;
  }
}
