import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/models/offre.dart';
import 'package:adfoot/models/user.dart';

class OffreController extends GetxController {
  static OffreController instance = Get.find();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Rx<List<Offre>> _offres = Rx<List<Offre>>([]);
  List<Offre> get offres => _offres.value;

  @override
  void onInit() {
    super.onInit();
    _fetchOffres();
  }

  /// Récupérer les offres depuis Firestore avec mise à jour du statut
  void _fetchOffres() {
    _firestore
        .collection('offres')
        .orderBy('dateCreation', descending: true)
        .snapshots()
        .listen((snapshot) async {
      List<Offre> fetched = [];

      for (var doc in snapshot.docs) {
        Offre offre = Offre.fromMap(doc.data());

        // Mise à jour automatique du statut si date dépassée
        if (offre.dateFin.isBefore(DateTime.now()) && offre.statut == 'ouverte') {
          await _firestore.collection('offres').doc(offre.id).update({'statut': 'fermée'});
          offre = Offre(
            id: offre.id,
            titre: offre.titre,
            description: offre.description,
            dateDebut: offre.dateDebut,
            dateFin: offre.dateFin,
            recruteur: offre.recruteur,
            candidats: offre.candidats,
            statut: 'fermée',
            dateCreation: offre.dateCreation,
          );
        }

        fetched.add(offre);
      }

      _offres.value = fetched;
      update();
    });
  }

  /// Publier une offre et notifier les joueurs
  Future<void> publierOffre(Offre offre, AppUser utilisateur) async {
    if (utilisateur.role != 'recruteur' && utilisateur.role != 'club') {
      Get.snackbar('Accès refusé',
          'Seuls les clubs ou recruteurs peuvent publier des offres.');
      return;
    }

    try {
      await _firestore.collection('offres').doc(offre.id).set(offre.toMap());
      Get.snackbar('Succès', 'Offre publiée avec succès.');
      await _notifierJoueurs(offre, utilisateur);
    } catch (e) {
      print('Erreur lors de la publication de l\'offre : $e');
      Get.snackbar('Erreur', 'Impossible de publier l\'offre : $e');
    }
  }

  /// Notifier les joueurs d'une nouvelle offre
  Future<void> _notifierJoueurs(Offre offre, AppUser recruteur) async {
    try {
      final joueursSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'joueur')
          .get();

      for (var joueurDoc in joueursSnapshot.docs) {
        final joueurData = joueurDoc.data();
        final fcmToken = joueurData['fcmToken'];

        if (fcmToken != null && fcmToken.isNotEmpty) {
          await PushNotificationService.sendNotification(
            title: 'Nouvelle Offre Disponible',
            body:
                'Une nouvelle offre a été publiée par ${recruteur.nom}. Découvrez-la maintenant.',
            token: fcmToken,
            contextType: 'offre',
            contextData: offre.id,
          );
        }
      }
    } catch (e) {
      print('Erreur lors de l\'envoi des notifications : $e');
      Get.snackbar('Erreur', 'Impossible d\'envoyer les notifications : $e');
    }
  }

  /// Modifier une offre existante
  Future<void> modifierOffre(Offre offre, AppUser utilisateur) async {
    if (utilisateur.uid != offre.recruteur.uid) {
      Get.snackbar(
          'Accès refusé', 'Vous ne pouvez modifier que vos propres offres.');
      return;
    }

    try {
      await _firestore.collection('offres').doc(offre.id).update(offre.toMap());
      Get.snackbar('Succès', 'Offre modifiée avec succès.');
    } catch (e) {
      print('Erreur lors de la modification de l\'offre : $e');
      Get.snackbar('Erreur', 'Impossible de modifier l\'offre : $e');
    }
  }

  /// Supprimer une offre
  Future<void> supprimerOffre(
      String offreId, AppUser utilisateur, Offre offre) async {
    if (utilisateur.uid != offre.recruteur.uid) {
      Get.snackbar(
          'Accès refusé', 'Vous ne pouvez supprimer que vos propres offres.');
      return;
    }

    try {
      await _firestore.collection('offres').doc(offreId).delete();
      Get.back();
      Get.snackbar('Succès', 'Offre supprimée avec succès.');
    } catch (e) {
      print('Erreur lors de la suppression de l\'offre : $e');
      Get.snackbar('Erreur', 'Impossible de supprimer l\'offre : $e');
    }
  }

  /// Permettre aux joueurs de postuler à une offre
  Future<void> postulerOffre(AppUser joueur, Offre offre) async {
    if (joueur.role != 'joueur') {
      Get.snackbar(
          'Accès refusé', 'Seuls les joueurs peuvent postuler à une offre.');
      return;
    }

    if (offre.statut == 'fermée') {
      Get.snackbar(
          'Offre fermée', 'Vous ne pouvez pas postuler à une offre fermée.');
      return;
    }

    bool dejaPostule = offre.candidats.any((c) => c.uid == joueur.uid);
    if (dejaPostule) {
      Get.snackbar(
          'Postulation existante', 'Vous avez déjà postulé à cette offre.');
      return;
    }

    try {
      final candidats = [...offre.candidats, joueur];
      await _firestore.collection('offres').doc(offre.id).update({
        'candidats': candidats.map((c) => c.toMap()).toList(),
      });
      Get.snackbar('Succès', 'Vous avez postulé à l\'offre.');
    } catch (e) {
      print('Erreur lors de la postulation : $e');
      Get.snackbar('Erreur', 'Impossible de postuler : $e');
    }
  }
}
