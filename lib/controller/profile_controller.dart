import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/auth_controller.dart';
import '../models/user.dart';

class ProfileController extends GetxController {
  final Rx<AppUser?> _user = Rx<AppUser?>(null); // Utilisateur actuel
  AppUser? get user => _user.value;

  final Rx<String> _uid = "".obs; // Stocke l'ID utilisateur à manipuler

  // Méthode pour mettre à jour l'ID utilisateur
  void updateUserId(String uid) {
    _uid.value = uid;
    getUserData();
  }

  // Méthode pour récupérer les données de l'utilisateur depuis Firestore
  Future<void> getUserData() async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid.value)
          .get();

      if (userDoc.exists) {
        _user.value = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
      } else {
        Get.snackbar('Erreur', 'Utilisateur introuvable');
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la récupération des données utilisateur');
    }

    update(); // Mise à jour de l'état GetX
  }

  // Méthode pour suivre/désuivre un utilisateur
  Future<void> followUser() async {
    try {
      // Assurer que l'utilisateur est défini avant d'accéder à uid
      if (AuthController.instance.user == null) {
        Get.snackbar('Erreur', 'Vous devez être connecté pour suivre un utilisateur.');
        return;
      }

      var doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid.value)
          .collection('followers')
          .doc(AuthController.instance.user!.uid)  // Utilisation du `!` après la vérification null-safe
          .get();

      if (!doc.exists) {
        // Ajouter un follower (incrémenter)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid.value)
            .update({'followers': FieldValue.increment(1)});

        // Ajouter dans following (incrémenter)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(AuthController.instance.user!.uid)
            .update({'followings': FieldValue.increment(1)});

        // Ajouter l'ID dans la liste de followers (optionnel si besoin)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid.value)
            .collection('followers')
            .doc(AuthController.instance.user!.uid)
            .set({});
      } else {
        // Supprimer un follower (décrémenter)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid.value)
            .update({'followers': FieldValue.increment(-1)});

        // Supprimer dans following (décrémenter)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(AuthController.instance.user!.uid)
            .update({'followings': FieldValue.increment(-1)});

        // Supprimer l'ID de la liste de followers (optionnel si besoin)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid.value)
            .collection('followers')
            .doc(AuthController.instance.user!.uid)
            .delete();
      }

      getUserData(); // Mise à jour des données après changement
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la modification du suivi');
    }
  }

  // Méthode pour mettre à jour le profil de l'utilisateur
  Future<void> updateUserProfile(AppUser updatedUser) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(updatedUser.uid)
          .update(updatedUser.toMap());

      _user.value = updatedUser;  // Mettre à jour localement
      update(); // Mise à jour de l'état après modification

      Get.snackbar('Succès', 'Profil mis à jour avec succès');
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la mise à jour du profil');
    }
  }

  // Méthode pour récupérer les followers d'un utilisateur (optionnel)
  Future<List<String>> getFollowers() async {
    List<String> followers = [];
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid.value)
          .collection('followers')
          .get();

      for (var doc in snapshot.docs) {
        followers.add(doc.id);
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la récupération des followers');
    }

    return followers;
  }

  // Méthode pour récupérer les followings d'un utilisateur (optionnel)
  Future<List<String>> getFollowings() async {
    List<String> followings = [];
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(AuthController.instance.user!.uid)  // Vérifier ici que `user` n'est pas null
          .collection('following')
          .get();

      for (var doc in snapshot.docs) {
        followings.add(doc.id);
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la récupération des followings');
    }

    return followings;
  }
}
