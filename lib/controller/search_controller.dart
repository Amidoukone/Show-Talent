import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/models/offre.dart';
import 'package:show_talent/models/user.dart';

class CustomSearchController extends GetxController {  // Renommage ici
  final Rx<List<AppUser>> _searchedUsers = Rx<List<AppUser>>([]);
  List<AppUser> get searchedUsers => _searchedUsers.value;

  final Rx<List<Offre>> _searchedOffres = Rx<List<Offre>>([]);
  List<Offre> get searchedOffres => _searchedOffres.value;

  // Méthode pour rechercher les utilisateurs par nom, rôle et localisation
  void search(String query, {String? role, String? location}) async {
    Query userQuery = FirebaseFirestore.instance.collection('users');

    // Filtrer les utilisateurs par rôle
    if (role != null && role.isNotEmpty) {
      userQuery = userQuery.where('role', isEqualTo: role);
    }

    // Filtrer les utilisateurs par localisation (si applicable)
    if (location != null && location.isNotEmpty) {
      userQuery = userQuery.where('location', isEqualTo: location);
    }

    // Rechercher par nom si une query est fournie
    if (query.isNotEmpty) {
      userQuery = userQuery
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff');
    }

    QuerySnapshot userSnapshot = await userQuery.get();
    _searchedUsers.value = userSnapshot.docs
        .map((doc) => AppUser.fromMap(doc.data() as Map<String, dynamic>))
        .toList();
  }

  // Méthode pour rechercher des offres avec des filtres (catégorie, dates)
  void searchOffres(String query, {String? category, DateTime? startDate, DateTime? endDate}) async {
    Query offreQuery = FirebaseFirestore.instance.collection('offres');

    if (category != null && category.isNotEmpty) {
      offreQuery = offreQuery.where('category', isEqualTo: category);
    }

    if (startDate != null && endDate != null) {
      offreQuery = offreQuery
          .where('dateDebut', isGreaterThanOrEqualTo: startDate)
          .where('dateFin', isLessThanOrEqualTo: endDate);
    }

    if (query.isNotEmpty) {
      offreQuery = offreQuery
          .where('titre', isGreaterThanOrEqualTo: query)
          .where('titre', isLessThanOrEqualTo: '$query\uf8ff');
    }

    QuerySnapshot offreSnapshot = await offreQuery.get();
    _searchedOffres.value = offreSnapshot.docs
        .map((doc) => Offre.fromMap(doc.data() as Map<String, dynamic>))
        .toList();
  }
}
