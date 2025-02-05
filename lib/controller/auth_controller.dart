import 'dart:io';
import 'package:adfoot/screens/main_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import '../screens/login_screen.dart';

class AuthController extends GetxController {
  static AuthController instance = Get.find();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  late Rx<User?> _firebaseUser;
  late final Rx<File?> _pickedImage = Rx<File?>(null);
  final Rx<AppUser?> _appUser = Rx<AppUser?>(null);
  bool _isNewlyRegistered = false;

  File? get profilePhoto => _pickedImage.value;
  AppUser? get user => _appUser.value;

  @override
  void onReady() {
    super.onReady();
    _firebaseUser = Rx<User?>(_auth.currentUser);
    _firebaseUser.bindStream(_auth.authStateChanges());
    ever(_firebaseUser, _setInitialScreen);
  }

  Future<void> _setInitialScreen(User? firebaseUser) async {
    if (firebaseUser == null) {
      _appUser.value = null;
      Get.offAll(() => const LoginScreen());
    } else {
      // Recharger l'utilisateur pour obtenir le statut de vérification actuel
      await firebaseUser.reload();
      final User? refreshedUser = _auth.currentUser;

      if (refreshedUser == null || !refreshedUser.emailVerified) {
        await signOut();
        _showSnackbar('Erreur', 'Veuillez vérifier votre email avant de vous connecter.', Colors.red);
        return;
      }

      if (!_isNewlyRegistered) {
        AppUser? appUser = await getAppUserFromFirestore(refreshedUser.uid);
        if (appUser != null) {
          _appUser.value = appUser;
          Get.offAll(() => const MainScreen());
        } else {
          await signOut();
        }
      } else {
        _isNewlyRegistered = false;
        Get.offAll(() => const LoginScreen());
      }
    }
  }

  Future<AppUser?> getAppUserFromFirestore(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      return doc.exists ? AppUser.fromMap(doc.data() as Map<String, dynamic>) : null;
    } catch (e) {
      debugPrint('Erreur récupération utilisateur : $e');
      return null;
    }
  }

  Future<void> pickImage() async {
    try {
      final pickedImage = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (pickedImage != null) {
        _pickedImage.value = File(pickedImage.path);
        _showSnackbar('Succès', 'Image ajoutée avec succès', Colors.green);
      }
    } catch (e) {
      _showSnackbar('Erreur', 'Erreur sélection image : $e', Colors.red);
    }
  }

  Future<String> _uploadToStorage(File image) async {
    try {
      Reference ref = _storage.ref().child('profilePictures/${_auth.currentUser!.uid}');
      UploadTask uploadTask = ref.putFile(image);
      return await (await uploadTask).ref.getDownloadURL();
    } catch (e) {
      throw Exception('Erreur upload image : $e');
    }
  }

  Future<void> registerUser(
    String name, String email, String password, String role, File? image,
    {Map<String, dynamic>? additionalData}
  ) async {
    if ([name, email, password, role].any((element) => element.isEmpty) || image == null) {
      _showSnackbar('Erreur', 'Tous les champs doivent être remplis.', Colors.red);
      return;
    }

    try {
      UserCredential userCred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await userCred.user!.sendEmailVerification();

      String downloadUrl = await _uploadToStorage(image);

      AppUser newUser = AppUser(
        uid: userCred.user!.uid,
        nom: name,
        email: email,
        role: role,
        photoProfil: downloadUrl,
        estActif: true,
        estBloque: false,
        followers: 0,
        followings: 0,
        dateInscription: DateTime.now(),
        dernierLogin: DateTime.now(),
        followersList: [],
        followingsList: [],
        nomClub: role == 'club' ? (additionalData?['nomClub'] ?? '') : null,
        ligue: role == 'club' ? (additionalData?['ligue'] ?? '') : null,
        entreprise: role == 'recruteur' ? (additionalData?['entreprise'] ?? '') : null,
        nombreDeRecrutements: role == 'recruteur' ? (additionalData?['nombreDeRecrutements'] ?? 0) : null,
        position: role == 'joueur' ? (additionalData?['position'] ?? '') : null,
        team: role == 'joueur' ? (additionalData?['team'] ?? '') : null,
      );

      await _firestore.collection('users').doc(userCred.user!.uid).set(newUser.toMap());
      _isNewlyRegistered = true;
      _showSnackbar('Succès', 'Inscription réussie. Vérifiez votre email.', Colors.green);
      Get.offAll(() => const LoginScreen());
    } catch (e) {
      _showSnackbar('Erreur', 'Erreur création compte : $e', Colors.red);
    }
  }

  Future<void> loginUser(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      _showSnackbar('Erreur', 'Tous les champs doivent être remplis.', Colors.red);
      return;
    }

    try {
      UserCredential userCred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      await userCred.user!.reload(); // Recharger les données utilisateur
      User? refreshedUser = userCred.user;

      if (refreshedUser == null || !refreshedUser.emailVerified) {
        await _auth.signOut();
        if (refreshedUser != null) {
          await refreshedUser.sendEmailVerification();
        }
        _showSnackbar('Erreur', 'Veuillez vérifier votre email. Un nouvel e-mail a été envoyé.', Colors.red);
        return;
      }

      AppUser? appUser = await getAppUserFromFirestore(refreshedUser.uid);
      if (appUser != null) {
        _appUser.value = appUser;
        Get.offAll(() => const MainScreen());
      } else {
        await signOut();
        _showSnackbar('Erreur', 'Erreur de connexion.', Colors.red);
      }
    } catch (e) {
      _showSnackbar('Erreur', 'Erreur de connexion : $e', Colors.red);
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _appUser.value = null;
    Get.offAll(() => const LoginScreen());
  }

  void _showSnackbar(String title, String message, Color color) {
    Get.snackbar(title, message, backgroundColor: color, colorText: Colors.white);
  }
}