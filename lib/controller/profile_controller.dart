import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/models/user.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileController extends GetxController {
  AppUser? user;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Charger le profil d'un utilisateur via son UID
  void updateUserId(String uid) {
    _firestore.collection('users').doc(uid).get().then((snapshot) {
      if (snapshot.exists) {
        user = AppUser.fromMap(snapshot.data()!);
        update();  // Met à jour l'état du contrôleur pour mettre à jour l'UI
      }
    }).catchError((e) {
      Get.snackbar('Erreur', 'Erreur lors du chargement du profil.');
    });
  }

  // Méthode pour mettre à jour la photo de profil dans Firestore
  Future<void> updateProfilePhoto(String uid, String photoUrl) async {
    try {
      await _firestore.collection('users').doc(uid).update({'photoProfil': photoUrl});
      user?.photoProfil = photoUrl;  // Mettre à jour la photo localement aussi
      update();  // Mise à jour de l'interface après changement
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la mise à jour de la photo de profil.');
    }
  }

  // Mise à jour complète du profil utilisateur
  Future<void> updateUserProfile(AppUser updatedUser) async {
    try {
      await _firestore.collection('users').doc(updatedUser.uid).update(updatedUser.toMap());
      user = updatedUser;
      update();  // Mettre à jour l'interface après la sauvegarde
      Get.snackbar('Succès', 'Profil mis à jour avec succès.');
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la mise à jour du profil.');
    }
  }

  // Suivre ou se désabonner d'un utilisateur
  Future<void> followUser() async {
    if (user == null || _auth.currentUser == null) return;

    String currentUserId = _auth.currentUser!.uid;
    String profileUserId = user!.uid;

    try {
      DocumentSnapshot<Map<String, dynamic>> currentUserSnapshot = 
          await _firestore.collection('users').doc(currentUserId).get();

      if (!currentUserSnapshot.exists) return;

      Map<String, dynamic> currentUserData = currentUserSnapshot.data()!;
      List<String> followings = List<String>.from(currentUserData['followings'] ?? []);

      if (followings.contains(profileUserId)) {
        // Si déjà suivi, désabonner
        followings.remove(profileUserId);
        user!.followers--;  // Réduire le nombre de followers
      } else {
        // Sinon, suivre
        followings.add(profileUserId);
        user!.followers++;  // Augmenter le nombre de followers
      }

      // Mettre à jour le profil actuel et le profil de l'utilisateur suivi
      await _firestore.collection('users').doc(currentUserId).update({'followings': followings});
      await _firestore.collection('users').doc(profileUserId).update({
        'followers': user!.followers,
      });

      update();  // Mise à jour de l'interface
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de suivre cet utilisateur.');
    }
  }

  // Méthode pour récupérer le profil utilisateur connecté
  AppUser? getLoggedInUser() {
    User? firebaseUser = _auth.currentUser;
    if (firebaseUser != null && user?.uid == firebaseUser.uid) {
      return user;
    }
    return null;
  }
}
