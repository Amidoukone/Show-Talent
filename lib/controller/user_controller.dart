import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/user.dart';

class UserController extends GetxController {
  static UserController instance = Get.find();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final Rx<AppUser?> _user = Rx<AppUser?>(null);
  AppUser? get user => _user.value;

  final Rx<List<AppUser>> _userList = Rx<List<AppUser>>([]);
  List<AppUser> get userList => _userList.value;

  bool _isNewlyRegistered = false;

  @override
  void onInit() {
    super.onInit();
    _bindUserStream();
    _fetchAllUsers();
  }

  void setNewlyRegistered(bool value) {
    _isNewlyRegistered = value;
  }

  void _bindUserStream() {
    _auth.authStateChanges().listen((User? firebaseUser) async {
      if (firebaseUser != null) {
        await _loadCurrentUser(firebaseUser.uid);
      } else {
        _user.value = null;
      }
    }, onError: (error) {
      debugPrint("Erreur de flux d'authentification : $error");
    });
  }

  Future<void> _loadCurrentUser(String uid) async {
    if (_isNewlyRegistered) {
      _isNewlyRegistered = false;
      return;
    }
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        _user.value = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
        await _updateFCMToken(uid);
      } else {
        _user.value = null;
        _showSnackbar("Inscription en cours", "Un email de validation vous sera envoyé", const Color.fromARGB(255, 5, 71, 29));
      }
    } catch (e) {
      _showSnackbar("Erreur", "Impossible de charger les informations utilisateur : $e", Colors.red);
    }
  }

  Future<void> _updateFCMToken(String uid) async {
    try {
      String? fcmToken = await _messaging.getToken();
      if (fcmToken != null) {
        await _firestore.collection('users').doc(uid).update({'fcmToken': fcmToken});
      }
    } catch (e) {
      debugPrint("Erreur lors de la mise à jour du token FCM : $e");
    }
  }

  void _fetchAllUsers() {
    _firestore.collection('users').snapshots().listen((snapshot) {
      try {
        _userList.value = snapshot.docs
            .map((doc) => AppUser.fromMap(doc.data()))
            .toList();
      } catch (e) {
        debugPrint("Erreur lors de la récupération des utilisateurs : $e");
      }
    }, onError: (error) {
      debugPrint("Erreur de flux Firestore : $error");
    });
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      _user.value = null;
      _showSnackbar("Déconnexion réussie", "Vous avez été déconnecté.", Colors.green);
    } catch (e) {
      _showSnackbar("Erreur", "Une erreur est survenue lors de la déconnexion : $e", Colors.red);
    }
  }

  void _showSnackbar(String title, String message, Color color) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: color,
      colorText: Colors.white,
    );
  }
}
