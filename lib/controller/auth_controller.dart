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

  late Rx<User?> _firebaseUser;  // Firebase User
  late Rx<File?> _pickedImage;   // Image sélectionnée
  final Rx<AppUser?> _user = Rx<AppUser?>(null);  // Utilisation de Rx<AppUser?> ici pour suivre les changements utilisateur

  AppUser? get user => _user.value;  // Getter sécurisé pour accéder à l'utilisateur

  File? get profilePhoto => _pickedImage.value;

  @override
  void onReady() {
    super.onReady();
    _firebaseUser = Rx<User?>(FirebaseAuth.instance.currentUser);
    _firebaseUser.bindStream(FirebaseAuth.instance.authStateChanges());
    ever(_firebaseUser, _setInitialScreen);
  }

  // Définir l'écran initial en fonction de l'état de connexion
  _setInitialScreen(User? firebaseUser) async {
    if (firebaseUser == null) {
      _user.value = null;  // Réinitialiser l'utilisateur local
      Get.offAll(() => const LoginScreen());
    } else {
      AppUser? appUser = await getAppUserFromFirestore(firebaseUser.uid);
      if (appUser != null) {
        _user.value = appUser;  // Stocker l'utilisateur récupéré
        Get.offAll(() => const HomeScreen());
        Get.find<NotificationController>().initCurrentUser();
      } else {
        Get.snackbar('Erreur', 'Utilisateur introuvable dans Firestore');
      }
    }
  }

  // Récupérer les informations de l'utilisateur depuis Firestore
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

  // Méthode pour choisir une image depuis la galerie
  void pickImage() async {
    final pickedImage = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedImage != null) {
      Get.snackbar('Photo de profil', 'Image ajoutée avec succès');
      _pickedImage = Rx<File?>(File(pickedImage.path));
    }
  }

  // Méthode pour uploader l'image dans Firebase Storage
  Future<String> _uploadToStorage(File image) async {
    Reference ref = FirebaseStorage.instance
        .ref()
        .child('profilePictures')
        .child(FirebaseAuth.instance.currentUser!.uid);

    UploadTask uploadTask = ref.putFile(image);
    TaskSnapshot snap = await uploadTask;
    String downloadUrl = await snap.ref.getDownloadURL();
    return downloadUrl;
  }

  // Méthode pour enregistrer un utilisateur avec un rôle spécifique
  void registerUser(String name, String email, String password, String role, File? image) async {
    try {
      if (name.isNotEmpty && email.isNotEmpty && password.isNotEmpty && image != null && role.isNotEmpty) {
        // Création de l'utilisateur avec Firebase Authentication
        UserCredential userCred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        // Upload de l'image de profil dans Firebase Storage
        String downloadUrl = await _uploadToStorage(image);

        // Création d'un nouvel utilisateur dans Firestore
        AppUser newUser = AppUser(
          uid: userCred.user!.uid,
          nom: name,
          email: email,
          role: role,
          photoProfil: downloadUrl,
          estActif: true,
          followers: 0,
          followings: 0,
          dateInscription: DateTime.now(),
          dernierLogin: DateTime.now(),
        );

        // Enregistrement de l'utilisateur dans Firestore
        await FirebaseFirestore.instance.collection('users').doc(userCred.user!.uid).set(newUser.toMap());

        _user.value = newUser;  // Stocker l'utilisateur dans GetX
        Get.snackbar('Bienvenue', 'Votre compte a été créé avec succès');
        Get.to(() => const HomeScreen());
      } else {
        Get.snackbar('Erreur', 'Veuillez remplir tous les champs et ajouter une photo');
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la création du compte : $e');
    }
  }

  // Connexion utilisateur avec email et mot de passe
  void loginUser(String email, String password) async {
    try {
      if (email.isNotEmpty && password.isNotEmpty) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
        Get.to(() => const HomeScreen());
      } else {
        Get.snackbar('Erreur', 'Veuillez remplir toutes les informations');
      }
    } catch (e) {
      Get.snackbar('Erreur de connexion', 'Erreur : $e');
    }
  }

  // Déconnexion de l'utilisateur
  void signOut() async {
    await FirebaseAuth.instance.signOut();
    _user.value = null;  // Réinitialiser l'utilisateur lors de la déconnexion
    Get.offAll(() => const LoginScreen());
  }
}
