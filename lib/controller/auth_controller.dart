import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/controller/notification_controller.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/screens/home_screen.dart';
import 'package:show_talent/screens/login_screen.dart';

class AuthController extends GetxController {
  static AuthController instance = Get.find();

  late Rx<User?> _firebaseUser;
  late Rx<File?> _pickedImage;
  final Rx<AppUser?> _user = Rx<AppUser?>(null);

  AppUser? get user => _user.value;
  File? get profilePhoto => _pickedImage.value;

  @override
  void onReady() {
    super.onReady();
    _firebaseUser = Rx<User?>(FirebaseAuth.instance.currentUser);
    _firebaseUser.bindStream(FirebaseAuth.instance.authStateChanges());
    ever(_firebaseUser, _setInitialScreen);
  }

  _setInitialScreen(User? firebaseUser) async {
    if (firebaseUser == null) {
      _user.value = null;
      Get.offAll(() => const LoginScreen());
    } else {
      AppUser? appUser = await getAppUserFromFirestore(firebaseUser.uid);
      if (appUser != null && appUser.estActif) {
        _user.value = appUser;
        Get.offAll(() => const HomeScreen());
        Get.find<NotificationController>().initCurrentUser();
      } else {
        await signOut();
        Get.snackbar(
          'Accès refusé',
          appUser == null
              ? 'Utilisateur introuvable dans Firestore'
              : 'Votre compte est bloqué.',
        );
      }
    }
  }

  Future<AppUser?> getAppUserFromFirestore(String uid) async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        return AppUser.fromMap(doc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer les informations utilisateur : $e');
    }
    return null;
  }

  void pickImage() async {
    final pickedImage = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedImage != null) {
      _pickedImage = Rx<File?>(File(pickedImage.path));
      Get.snackbar('Photo de profil', 'Image ajoutée avec succès');
    }
  }

  Future<String> _uploadToStorage(File image) async {
    Reference ref = FirebaseStorage.instance
        .ref()
        .child('profilePictures')
        .child(FirebaseAuth.instance.currentUser!.uid);

    UploadTask uploadTask = ref.putFile(image);
    TaskSnapshot snap = await uploadTask;
    return await snap.ref.getDownloadURL();
  }

  void registerUser(String name, String email, String password, String role, File? image) async {
    try {
      if (name.isNotEmpty && email.isNotEmpty && password.isNotEmpty && image != null && role.isNotEmpty) {
        UserCredential userCred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

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
        );

        await FirebaseFirestore.instance.collection('users').doc(userCred.user!.uid).set(newUser.toMap());
        _user.value = newUser;
        Get.offAll(() => const HomeScreen());
      } else {
        Get.snackbar('Erreur', 'Veuillez remplir tous les champs et ajouter une photo');
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la création du compte : $e');
    }
  }

  void loginUser(String email, String password) async {
    try {
      if (email.isNotEmpty && password.isNotEmpty) {
        UserCredential userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);

        AppUser? appUser = await getAppUserFromFirestore(userCred.user!.uid);
        if (appUser != null && appUser.estActif) {
          _user.value = appUser;
          Get.offAll(() => const HomeScreen());
        } else {
          await signOut();
          Get.snackbar('Accès refusé', appUser == null ? 'Utilisateur introuvable' : 'Votre compte est bloqué.');
        }
      } else {
        Get.snackbar('Erreur', 'Veuillez remplir toutes les informations');
      }
    } catch (e) {
      Get.snackbar('Erreur de connexion', 'Erreur : $e');
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    _user.value = null;
    Get.offAll(() => const LoginScreen());
  }

  Future<void> forgotPassword(String email) async {
    if (email.isEmpty) {
      Get.snackbar('Erreur', 'Veuillez entrer votre email pour réinitialiser le mot de passe.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      Get.snackbar('Réinitialisation du mot de passe', 'Un email de réinitialisation vous a été envoyé.');
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    }
  }
}
