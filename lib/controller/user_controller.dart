import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';

class UserController extends GetxController {
  final Rx<AppUser?> _user = Rx<AppUser?>(null);
  AppUser? get user => _user.value;

  @override
  void onInit() {
    super.onInit();
    _bindUserStream();
  }

  // Cette méthode écoute les changements d'authentification et met à jour les informations utilisateur
  void _bindUserStream() {
    FirebaseAuth.instance.authStateChanges().listen((User? firebaseUser) async {
      if (firebaseUser != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(firebaseUser.uid)
            .get();
        _user.value = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
      } else {
        _user.value = null;
      }
    });
  }

  // Méthode pour déconnecter l'utilisateur
  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    _user.value = null;
  }
}
