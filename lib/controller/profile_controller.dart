import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/models/user.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProfileController extends GetxController {
  AppUser? user;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  var isLoadingPhoto = false.obs;

  void updateUserId(String uid) {
    _firestore.collection('users').doc(uid).get().then((snapshot) {
      if (snapshot.exists) {
        user = AppUser.fromMap(snapshot.data()!);
        update();
      }
    }).catchError((e) {
      Get.snackbar('Erreur', 'Erreur lors du chargement du profil.');
    });
  }

  Future<void> updateProfilePhoto(String uid, String photoPath) async {
    try {
      isLoadingPhoto.value = true;  // Démarre le chargement
      String photoUrl = await _uploadPhotoToStorage(uid, photoPath);
      await _firestore.collection('users').doc(uid).update({'photoProfil': photoUrl});
      user?.photoProfil = photoUrl;
      update();  // Met à jour le profil après la mise à jour de la photo
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la mise à jour de la photo de profil.');
    } finally {
      isLoadingPhoto.value = false;  // Arrête le chargement
    }
  }

  Future<String> _uploadPhotoToStorage(String uid, String filePath) async {
    final ref = _storage.ref().child('profilePhotos/$uid');
    await ref.putFile(File(filePath));
    return await ref.getDownloadURL();
  }

  Future<void> updateUserProfile(AppUser updatedUser) async {
    try {
      await _firestore.collection('users').doc(updatedUser.uid).update(updatedUser.toMap());
      user = updatedUser;
      update();
      Get.snackbar('Succès', 'Profil mis à jour avec succès.');
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la mise à jour du profil.');
    }
  }

  // Méthode pour gérer l'abonnement d'un utilisateur
  Future<void> followUser() async {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (user == null || currentUserId == null || currentUserId == user!.uid) return;

    String profileUserId = user!.uid;

    try {
      DocumentSnapshot<Map<String, dynamic>> currentUserSnapshot =
          await _firestore.collection('users').doc(currentUserId).get();

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
      await _firestore.collection('users').doc(profileUserId).update({
        'followers': user!.followers,
      });

      update();
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de suivre cet utilisateur.');
    }
  }

  AppUser? getLoggedInUser() {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null && user?.uid == currentUserId) {
      return user;
    }
    return null;
  }
}
