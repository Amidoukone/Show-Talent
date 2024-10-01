import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/auth_controller.dart';
import 'package:show_talent/models/offre.dart';
import 'package:show_talent/models/user.dart';

class OffreController extends GetxController {
  static OffreController instance = Get.find();

  RxList<Offre> offres = <Offre>[].obs;
  RxList<Offre> offresFiltrees = <Offre>[].obs;

  // Récupérer toutes les offres depuis Firestore
  Future<void> getAllOffres() async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('offres')
          .orderBy('dateDebut', descending: true)
          .get();

      offres.value = snapshot.docs
          .map((doc) => Offre.fromMap(doc.data() as Map<String, dynamic>))
          .toList();

      offresFiltrees.value = List<Offre>.from(offres);
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer les offres : $e');
    }
  }

  // Publier une nouvelle offre
  Future<void> publierOffre(String titre, String description, DateTime dateDebut, DateTime dateFin) async {
    AppUser? recruteur = AuthController.instance.user;

    if (recruteur == null || (recruteur.role != 'recruteur' && recruteur.role != 'club')) {
      Get.snackbar('Erreur', 'Seuls les recruteurs ou clubs peuvent publier des offres');
      return;
    }

    try {
      String id = FirebaseFirestore.instance.collection('offres').doc().id;

      Offre newOffre = Offre(
        id: id,
        titre: titre,
        description: description,
        dateDebut: dateDebut,
        dateFin: dateFin,
        recruteur: recruteur,
        candidats: [],
        statut: 'ouverte',
      );

      await FirebaseFirestore.instance.collection('offres').doc(id).set(newOffre.toMap());
      await getAllOffres();  // Rafraîchir la liste des offres
      Get.snackbar('Succès', 'Offre publiée avec succès');
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de publier l\'offre : $e');
    }
  }

  // Modifier une offre existante
  Future<void> modifierOffre(String id, String titre, String description, DateTime dateDebut, DateTime dateFin) async {
    try {
      await FirebaseFirestore.instance.collection('offres').doc(id).update({
        'titre': titre,
        'description': description,
        'dateDebut': dateDebut,
        'dateFin': dateFin,
      });
      await getAllOffres();  // Rafraîchir la liste des offres après modification
      Get.snackbar('Succès', 'Offre modifiée avec succès');
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la modification de l\'offre : $e');
    }
  }

  // Supprimer une offre existante avec confirmation
  Future<void> supprimerOffre(String id) async {
    try {
      await FirebaseFirestore.instance.collection('offres').doc(id).delete();
      await getAllOffres();  // Rafraîchir la liste des offres après suppression
      Get.snackbar('Succès', 'Offre supprimée avec succès');
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la suppression de l\'offre : $e');
    }
  }

  // Méthode pour permettre à un joueur de postuler à une offre
  Future<void> postulerOffre(Offre offre) async {
    AppUser? joueur = AuthController.instance.user;

    if (joueur == null || joueur.role != 'joueur') {
      Get.snackbar('Erreur', 'Seuls les joueurs peuvent postuler à cette offre');
      return;
    }

    try {
      if (!offre.candidats.any((c) => c.uid == joueur.uid)) {
        offre.candidats.add(joueur);

        // Mettre à jour les candidats de l'offre dans Firestore
        await FirebaseFirestore.instance
            .collection('offres')
            .doc(offre.id)
            .update({
          'candidats': offre.candidats.map((c) => c.toMap()).toList(),
        });

        Get.snackbar('Succès', 'Vous avez postulé à l\'offre');
      } else {
        Get.snackbar('Erreur', 'Vous avez déjà postulé à cette offre');
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la soumission de candidature : $e');
    }
  }
}
