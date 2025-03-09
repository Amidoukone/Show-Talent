import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/controller/user_controller.dart';

class ProfileController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  AppUser? user;
  var isLoadingPhoto = false.obs;
  var videoList = <Video>[].obs;

  /// Mise à jour de l'ID utilisateur
  void updateUserId(String uid) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        user = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
        fetchUserVideos(uid);
        update();
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors du chargement du profil.', backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  /// Mise à jour de la photo de profil
  Future<void> updateProfilePhoto(String uid, String photoPath) async {
    try {
      isLoadingPhoto.value = true;

      // Téléchargement et mise à jour de la photo
      String photoUrl = await _uploadPhotoToStorage(uid, photoPath);
      await _firestore.collection('users').doc(uid).update({'photoProfil': photoUrl});
      
      // Mise à jour locale de l'utilisateur
      user?.photoProfil = photoUrl;
      update();

      // Mise à jour globale dans `UserController`
      final userController = Get.find<UserController>();
      await userController.refreshUserData();

      Get.snackbar('Succès', 'Photo de profil mise à jour avec succès.', backgroundColor: Colors.green, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la mise à jour de la photo.', backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      isLoadingPhoto.value = false;
    }
  }

  /// Téléversement de la photo vers Firebase Storage
  Future<String> _uploadPhotoToStorage(String uid, String filePath) async {
    final ref = _storage.ref().child('profilePhotos/$uid');
    await ref.putFile(File(filePath));
    return await ref.getDownloadURL();
  }

  /// Récupération des vidéos de l'utilisateur
  void fetchUserVideos(String uid) async {
    try {
      final QuerySnapshot snapshot = await _firestore.collection('videos').where('uid', isEqualTo: uid).get();

      videoList.value = snapshot.docs.map((doc) => Video.fromMap(doc.data() as Map<String, dynamic>)).toList();
    } catch (e) {
      Get.snackbar('Erreur', 'Échec du chargement des vidéos.', backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  /// Mise à jour des informations utilisateur
  Future<void> updateUserProfile(AppUser updatedUser) async {
    try {
      await _firestore.collection('users').doc(updatedUser.uid).update(updatedUser.toMap());
      user = updatedUser;
      update();

      //  Mise à jour globale dans `UserController`
      final userController = Get.find<UserController>();
      await userController.refreshUserData();

      Get.snackbar('Succès', 'Profil mis à jour avec succès.', backgroundColor: Colors.green, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la mise à jour du profil.', backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  /// Gérer Follow / Unfollow
  Future<void> followUser() async {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (user == null || currentUserId == null || currentUserId == user!.uid) {
      return;
    }

    String profileUserId = user!.uid;

    try {
      DocumentSnapshot<Map<String, dynamic>> currentUserSnapshot = await _firestore.collection('users').doc(currentUserId).get();
      if (!currentUserSnapshot.exists) return;

      Map<String, dynamic> currentUserData = currentUserSnapshot.data()!;
      List<String> followings = List<String>.from(currentUserData['followings'] ?? []);

      if (followings.contains(profileUserId)) {
        followings.remove(profileUserId);
        user!.followers--;
      } else {
        followings.add(profileUserId);
        user!.followers++;
      }

      await _firestore.collection('users').doc(currentUserId).update({'followings': followings});
      await _firestore.collection('users').doc(profileUserId).update({'followers': user!.followers});

      update();
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de suivre cet utilisateur.', backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  /// 👤 **Obtenir l'utilisateur actuellement connecté**
  AppUser? getLoggedInUser() {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null && user?.uid == currentUserId) {
      return user;
    }
    return null;
  }
}
