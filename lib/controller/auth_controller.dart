import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';

class AuthController extends GetxController {
  static AuthController instance = Get.find();

  late Rx<User?> _firebaseUser;
  late Rx<File?> _pickedImage;
  final Rx<AppUser?> _appUser = Rx<AppUser?>(null);

  File? get profilePhoto => _pickedImage.value;
  AppUser? get user => _appUser.value;

  @override
  void onReady() {
    super.onReady();
    _firebaseUser = Rx<User?>(FirebaseAuth.instance.currentUser);
    _firebaseUser.bindStream(FirebaseAuth.instance.authStateChanges());
    ever(_firebaseUser, _setInitialScreen);
  }

  /// Définir l'écran initial en fonction de l'état de connexion
  Future<void> _setInitialScreen(User? firebaseUser) async {
    if (firebaseUser == null) {
      _appUser.value = null;
      Get.offAll(() => const LoginScreen());
    } else {
      AppUser? appUser = await getAppUserFromFirestore(firebaseUser.uid);
      if (appUser != null) {
        _appUser.value = appUser;
        Get.offAll(() => const HomeScreen());
      } else {
        Get.snackbar('Erreur', 'Utilisateur introuvable dans la base de données');
        await signOut();
      }
    }
  }

  /// Récupérer les données utilisateur depuis Firestore
  Future<AppUser?> getAppUserFromFirestore(String uid) async {
    try {
      DocumentSnapshot doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        return AppUser.fromMap(doc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      _showErrorSnackbar('Impossible de récupérer les informations utilisateur : $e');
    }
    return null;
  }

  /// Sélectionner une image pour le profil
  void pickImage() async {
    try {
      final pickedImage = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (pickedImage != null) {
        _pickedImage = Rx<File?>(File(pickedImage.path));
        _showSuccessSnackbar('Image ajoutée avec succès');
      }
    } catch (e) {
      _showErrorSnackbar('Erreur lors de la sélection de l\'image : $e');
    }
  }

  /// Uploader une image dans Firebase Storage
  Future<String> _uploadToStorage(File image) async {
    try {
      Reference ref = FirebaseStorage.instance
          .ref()
          .child('profilePictures')
          .child(FirebaseAuth.instance.currentUser!.uid);

      UploadTask uploadTask = ref.putFile(image);
      TaskSnapshot snap = await uploadTask;
      return await snap.ref.getDownloadURL();
    } catch (e) {
      throw Exception('Erreur lors du téléchargement de l\'image : $e');
    }
  }

  /// Inscrire un nouvel utilisateur
  void registerUser(
      String name, String email, String password, String role, File? image,
      {Map<String, dynamic>? additionalData}) async {
    if (name.isEmpty || email.isEmpty || password.isEmpty || role.isEmpty || image == null) {
      _showErrorSnackbar('Tous les champs doivent être remplis.');
      return;
    }

    try {
      UserCredential userCred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

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
        nombreDeRecrutements: role == 'recruteur'
            ? (additionalData?['nombreDeRecrutements'] ?? 0)
            : null,
        position: role == 'joueur' ? (additionalData?['position'] ?? '') : null,
        team: role == 'joueur' ? (additionalData?['team'] ?? '') : null,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCred.user!.uid)
          .set(newUser.toMap());

      _showSuccessSnackbar('Inscription réussie. Vérifiez votre email.');
      await signOut();
    } catch (e) {
      _showErrorSnackbar('Erreur lors de la création du compte : $e');
    }
  }

  /// Connexion de l'utilisateur
  void loginUser(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      _showErrorSnackbar('Tous les champs doivent être remplis.');
      return;
    }

    try {
      UserCredential userCred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      if (!userCred.user!.emailVerified) {
        await userCred.user!.sendEmailVerification();
        _showErrorSnackbar('Veuillez vérifier votre email avant de vous connecter.');
        await signOut();
        return;
      }

      AppUser? appUser = await getAppUserFromFirestore(userCred.user!.uid);
      if (appUser != null && appUser.estActif) {
        _appUser.value = appUser;
        Get.offAll(() => const HomeScreen());
      } else {
        await signOut();
        _showErrorSnackbar('Utilisateur bloqué ou introuvable.');
      }
    } catch (e) {
      _showErrorSnackbar('Erreur de connexion : $e');
    }
  }

  /// Déconnexion
  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    _appUser.value = null;
    Get.offAll(() => const LoginScreen());
  }

  /// Helpers pour afficher les messages
  void _showSuccessSnackbar(String message) {
    Get.snackbar('Succès', message, backgroundColor: Colors.green, colorText: Colors.white);
  }

  void _showErrorSnackbar(String message) {
    Get.snackbar('Erreur', message, backgroundColor: Colors.red, colorText: Colors.white);
  }
}
