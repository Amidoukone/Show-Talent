import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';

class UserController extends GetxController {
  // Observables pour l'utilisateur actuel et la liste des utilisateurs
  final Rx<AppUser?> _user = Rx<AppUser?>(null); // Utilisateur actuel observable
  AppUser? get user => _user.value; // Getter pour accéder à l'utilisateur actuel

  final Rx<List<AppUser>> _userList = Rx<List<AppUser>>([]);  // Liste des utilisateurs observable
  List<AppUser> get userList => _userList.value; // Getter pour accéder à la liste des utilisateurs

  @override
  void onInit() {
    super.onInit();
    _bindUserStream(); // Écouter les changements d'état de connexion de l'utilisateur actuel
    _fetchAllUsers();  // Charger la liste des utilisateurs dès le démarrage
  }

  // Méthode pour écouter les changements d'état de connexion de l'utilisateur actuel
  void _bindUserStream() {
    FirebaseAuth.instance.authStateChanges().listen((User? firebaseUser) async {
      if (firebaseUser != null) {
        // Si l'utilisateur est connecté, récupérer ses informations depuis Firestore
        try {
          DocumentSnapshot userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(firebaseUser.uid)
              .get();
          if (userDoc.exists && userDoc.data() != null) {
            _user.value = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
            print("Utilisateur actuel récupéré: ${_user.value?.nom}");
          } else {
            print("Erreur: Le document utilisateur n'existe pas ou est vide.");
            _user.value = null; // Si les données sont invalides, on réinitialise l'utilisateur
          }
        } catch (e) {
          print("Erreur lors de la récupération de l'utilisateur actuel: $e");
        }
      } else {
        // Si l'utilisateur se déconnecte ou n'est pas connecté, réinitialiser l'utilisateur
        print("Utilisateur déconnecté");
        _user.value = null;
      }
    });
  }

  // Méthode pour récupérer tous les utilisateurs depuis Firestore en temps réel
  void _fetchAllUsers() {
    FirebaseFirestore.instance.collection('users').snapshots().listen((snapshot) {
      try {
        // Mapper les documents Firestore en objets AppUser et ignorer les documents invalides
        _userList.value = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>?;

          // Vérification que les données existent et que 'uid' est non-null
          if (data != null && data['uid'] != null) {
            return AppUser.fromMap(data);
          } else {
            print("Document utilisateur invalide détecté: $data");
            return null; // Ignorer les documents vides ou malformés
          }
        }).whereType<AppUser>().toList(); // Filtrer les utilisateurs valides uniquement

        // Afficher la taille de la liste chargée pour le débogage
        print("Nombre d'utilisateurs chargés: ${_userList.value.length}");
      } catch (e) {
        print("Erreur lors de la récupération de la liste des utilisateurs: $e");
      }
    });
  }

  // Méthode pour déconnecter l'utilisateur actuel
  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut(); // Déconnexion de Firebase
      _user.value = null; // Réinitialiser l'utilisateur actuel après déconnexion
      print("Déconnexion réussie");
    } catch (e) {
      print("Erreur lors de la déconnexion: $e");
    }
  }
}
