
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/auth_controller.dart';
import '../models/user.dart';

class ProfileController extends GetxController {
  final Rx<AppUser?> _user = Rx<AppUser?>(null);
  AppUser? get user => _user.value;

  final Rx<String> _uid = "".obs;

  // Méthode pour mettre à jour l'ID utilisateur
  updateUserId(String uid) {
    _uid.value = uid;
    getUserData();
  }

  // Méthode pour récupérer les données de l'utilisateur depuis Firestore
  getUserData() async {
    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid.value)
        .get();

    if (userDoc.exists) {
      _user.value = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
    }

    update();
  }

  // Méthode pour suivre/désuivre un utilisateur
  followUser() async {
    var doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid.value)
        .collection('followers')
        .doc(AuthController.instance.user.uid)  // Remplacement ici
        .get();

    if (!doc.exists) {
      // Ajouter à la collection des followers
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid.value)
          .collection('followers')
          .doc(AuthController.instance.user.uid)  // Remplacement ici
          .set({});

      // Ajouter à la collection des following
      await FirebaseFirestore.instance
          .collection('users')
          .doc(AuthController.instance.user.uid)  // Remplacement ici
          .collection('following')
          .doc(_uid.value)
          .set({});

      _user.value!.followers.add(AuthController.instance.user.uid);  // Remplacement ici
    } else {
      // Supprimer des followers
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid.value)
          .collection('followers')
          .doc(AuthController.instance.user.uid)  // Remplacement ici
          .delete();

      // Supprimer des following
      await FirebaseFirestore.instance
          .collection('users')
          .doc(AuthController.instance.user.uid)  // Remplacement ici
          .collection('following')
          .doc(_uid.value)
          .delete();

      _user.value!.followers.remove(AuthController.instance.user.uid);  // Remplacement ici
    }

    update();
  }
}
