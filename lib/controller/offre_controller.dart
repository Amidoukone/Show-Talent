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

  /// Récupérer les offres depuis Firestore
  void _fetchOffres() {
    _firestore.collection('offres').snapshots().listen((snapshot) {
      _offres.value =
          snapshot.docs.map((doc) => Offre.fromMap(doc.data())).toList();
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
      // Enregistrer l'offre dans Firestore
      await _firestore.collection('offres').doc(offre.id).set(offre.toMap());
      Get.snackbar('Succès', 'Offre publiée avec succès.');

      // Notifier les joueurs
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
          print('Notification envoyée au joueur : ${joueurData['nom']}');
        } else {
          print('Token FCM manquant pour le joueur : ${joueurData['nom']}');
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

      // Fermer le dialogue après suppression
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
