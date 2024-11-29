import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/models/offre.dart';
import 'package:show_talent/models/user.dart';

class OffreController extends GetxController {
  static OffreController instance = Get.find();

  final Rx<List<Offre>> _offres = Rx<List<Offre>>([]);
  List<Offre> get offres => _offres.value;

  @override
  void onInit() {
    super.onInit();
    _fetchOffres();
  }

  // Récupérer les offres depuis Firestore
  void _fetchOffres() {
    FirebaseFirestore.instance.collection('offres').snapshots().listen((snapshot) {
      _offres.value = snapshot.docs.map((doc) {
        return Offre.fromMap(doc.data());
      }).toList();
    });
  }

  // Publier une offre
  Future<void> publierOffre(Offre offre, AppUser utilisateur) async {
    if (utilisateur.role != 'recruteur' && utilisateur.role != 'club') {
      Get.snackbar('Accès refusé', 'Seuls les clubs ou recruteurs peuvent publier des offres.');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('offres').doc(offre.id).set(offre.toMap());
      Get.snackbar('Succès', 'Offre publiée avec succès.');
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de publier l\'offre : $e');
    }
  }

  // Modifier une offre existante
  Future<void> modifierOffre(Offre offre, AppUser utilisateur) async {
    if (utilisateur.uid != offre.recruteur.uid) {
      Get.snackbar('Accès refusé', 'Vous ne pouvez modifier que vos propres offres.');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('offres').doc(offre.id).update(offre.toMap());
      Get.snackbar('Succès', 'Offre modifiée avec succès.');
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de modifier l\'offre : $e');
    }
  }

  // Supprimer une offre avec confirmation
  Future<void> supprimerOffre(String offreId, AppUser utilisateur, Offre offre) async {
    if (utilisateur.uid != offre.recruteur.uid) {
      Get.snackbar('Accès refusé', 'Vous ne pouvez supprimer que vos propres offres.');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('offres').doc(offreId).delete();
      Get.snackbar('Succès', 'Offre supprimée avec succès.');
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de supprimer l\'offre : $e');
    }
  }

  // Permettre aux joueurs de postuler à une offre
  Future<void> postulerOffre(AppUser joueur, Offre offre) async {
    if (joueur.role != 'joueur') {
      Get.snackbar('Accès refusé', 'Seuls les joueurs peuvent postuler à une offre.');
      return;
    }
    if (offre.statut == 'fermée') {
      Get.snackbar('Offre fermée', 'Vous ne pouvez pas postuler à une offre fermée.');
      return;
    }

    // Vérifier si le joueur a déjà postulé
    bool dejaPostule = offre.candidats.any((c) => c.uid == joueur.uid);
    if (dejaPostule) {
      Get.snackbar('Postulation existante', 'Vous avez déjà postulé à cette offre.');
      return;
    }

    try {
      final candidats = [...offre.candidats, joueur];
      await FirebaseFirestore.instance.collection('offres').doc(offre.id).update({
        'candidats': candidats.map((c) => c.toMap()).toList(),
      });
      Get.snackbar('Succès', 'Vous avez postulé à l\'offre.');
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de postuler : $e');
    }
  }

  // Permettre aux joueurs d'annuler leur postulation
  Future<void> annulerPostulation(AppUser joueur, Offre offre) async {
    if (joueur.role != 'joueur') {
      Get.snackbar('Accès refusé', 'Seuls les joueurs peuvent annuler leur postulation.');
      return;
    }

    try {
      final candidats = offre.candidats.where((c) => c.uid != joueur.uid).toList();
      await FirebaseFirestore.instance.collection('offres').doc(offre.id).update({
        'candidats': candidats.map((c) => c.toMap()).toList(),
      });
      Get.snackbar('Succès', 'Postulation annulée avec succès.');
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible d\'annuler la postulation : $e');
    }
  }

  // Changer le statut d'une offre (ouverte/fermée)
  Future<void> changerStatutOffre(Offre offre, AppUser utilisateur, String statut) async {
    if (utilisateur.uid != offre.recruteur.uid) {
      Get.snackbar('Accès refusé', 'Vous ne pouvez changer le statut que de vos propres offres.');
      return;
    }

    try {
      offre.statut = statut;
      await FirebaseFirestore.instance.collection('offres').doc(offre.id).update({
        'statut': statut,
      });
      Get.snackbar('Succès', 'Le statut de l\'offre a été mis à jour : $statut.');
      update();
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de changer le statut : $e');
    }
  }

  // Récupérer la liste des candidats pour une offre
  Future<List<AppUser>> fetchCandidats(Offre offre) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('offres').doc(offre.id).get();
      final data = doc.data();
      if (data == null) return [];
      final candidats = List<AppUser>.from(
        (data['candidats'] as List<dynamic>?)?.map((c) => AppUser.fromMap(c)) ?? [],
      );
      return candidats;
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer les candidats : $e');
      return [];
    }
  }
}
