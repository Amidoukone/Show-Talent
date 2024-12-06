import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get/get.dart';
import '../models/user.dart';

class UserController extends GetxController {
  final Rx<AppUser?> _user = Rx<AppUser?>(null);
  AppUser? get user => _user.value;

  final Rx<List<AppUser>> _userList = Rx<List<AppUser>>([]);
  List<AppUser> get userList => _userList.value;

  @override
  void onInit() {
    super.onInit();
    _bindUserStream();
    _fetchAllUsers();
  }

  void _bindUserStream() {
    FirebaseAuth.instance.authStateChanges().listen((User? firebaseUser) async {
      if (firebaseUser != null) {
        await _loadCurrentUser(firebaseUser.uid);
      } else {
        _user.value = null;
      }
    });
  }

  Future<void> _loadCurrentUser(String uid) async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        _user.value = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
        await _updateFCMToken(uid);
      } else {
        _user.value = null;
      }
    } catch (e) {
      print("Erreur lors de la récupération de l'utilisateur actuel: $e");
      Get.snackbar("Erreur", "Impossible de charger les informations de l'utilisateur.");
    }
  }

  Future<void> _updateFCMToken(String uid) async {
    try {
      String? fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'fcmToken': fcmToken,
        });
      }
    } catch (e) {
      print("Erreur lors de la mise à jour du token FCM: $e");
    }
  }

  void _fetchAllUsers() {
    FirebaseFirestore.instance.collection('users').snapshots().listen((snapshot) {
      try {
        _userList.value = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null) {
            return AppUser.fromMap(data);
          }
          return null;
        }).whereType<AppUser>().toList();
      } catch (e) {
        print("Erreur lors de la récupération de la liste des utilisateurs: $e");
      }
    });
  }

  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      _user.value = null;
    } catch (e) {
      print("Erreur lors de la déconnexion: $e");
    }
  }
}
