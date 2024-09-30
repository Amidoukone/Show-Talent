import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/auth_controller.dart';
import 'package:show_talent/controller/notification_controller.dart';
import 'package:show_talent/models/notification.dart';
import 'package:show_talent/models/offre.dart';
import 'package:show_talent/models/user.dart';

class OffreController extends GetxController {
  static OffreController instance = Get.find();

  RxList<Offre> offres = <Offre>[].obs;  // Liste complète des offres
  RxList<Offre> offresFiltrees = <Offre>[].obs;  // Liste filtrée des offres

  final NotificationController notificationController = Get.put(NotificationController());

  // Récupérer toutes les offres depuis Firestore
  Future<void> getAllOffres() async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('offres')
          .orderBy('dateDebut', descending: true)
          .get();

      // Transformation des données en objets Offre
      offres.value = snapshot.docs
          .map((doc) => Offre.fromMap(doc.data() as Map<String, dynamic>))
          .toList();

      // Initialiser la liste filtrée avec toutes les offres
      offresFiltrees.value = List<Offre>.from(offres);

      print('Offres récupérées avec succès');
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer les offres : $e');
    }
  }

  // Publier une nouvelle offre
  Future<void> publierOffre(String titre, String description, DateTime dateDebut, DateTime dateFin) async {
    AppUser? recruteur = AuthController.instance.user;

    // Vérification du rôle avant publication
    if (recruteur == null || (recruteur.role != 'recruteur' && recruteur.role != 'club')) {
      Get.snackbar('Erreur', 'Seuls les recruteurs ou clubs peuvent publier des offres');
      return;
    }

    try {
      // Création d'un nouvel ID pour l'offre
      String id = FirebaseFirestore.instance.collection('offres').doc().id;

      // Nouvelle instance de l'offre
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

      // Enregistrement de l'offre dans Firestore
      await FirebaseFirestore.instance.collection('offres').doc(id).set(newOffre.toMap());

      // Récupérer les joueurs cibles pour notification
      List<AppUser> joueurs = await getJoueursCibles();
      for (var joueur in joueurs) {
        NotificationModel notification = NotificationModel(
          id: FirebaseFirestore.instance.collection('notifications').doc().id,
          destinataire: joueur,
          message: 'Nouvelle offre disponible : $titre',
          type: 'offre',
          dateCreation: DateTime.now(),
        );
        await notificationController.sendNotification(notification);
      }

      // Recharger toutes les offres après publication
      await getAllOffres();
      Get.snackbar('Succès', 'Offre publiée avec succès');
    } catch (e) {
      print("Erreur lors de la publication: $e");
      Get.snackbar('Erreur', 'Impossible de publier l\'offre : $e');
    }
  }

  // Filtrer les offres selon leur statut
  void filtrerOffresParStatut(String statut) {
    if (statut == 'toutes') {
      offresFiltrees.value = List<Offre>.from(offres);  // Afficher toutes les offres si "toutes" est sélectionné
    } else {
      offresFiltrees.value = offres.where((offre) => offre.statut == statut).toList();
    }
  }

  // Récupérer les joueurs cibles pour les notifications
  Future<List<AppUser>> getJoueursCibles() async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'joueur')
          .get();

      return snapshot.docs
          .map((doc) => AppUser.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer les joueurs : $e');
      return [];
    }
  }

  // Permettre à un joueur de postuler à une offre
  Future<void> postulerOffre(Offre offre) async {
    AppUser? joueur = AuthController.instance.user;

    // Vérification du rôle avant de postuler
    if (joueur == null || joueur.role != 'joueur') {
      Get.snackbar('Erreur', 'Seuls les joueurs peuvent postuler à cette offre');
      return;
    }

    try {
      // Vérifier si le joueur a déjà postulé
      if (!offre.candidats.contains(joueur)) {
        offre.candidats.add(joueur);

        // Mettre à jour les candidats de l'offre dans Firestore
        await FirebaseFirestore.instance
            .collection('offres')
            .doc(offre.id)
            .update({'candidats': offre.candidats.map((j) => j.toMap()).toList()});

        Get.snackbar('Succès', 'Vous avez postulé à l\'offre');
      } else {
        Get.snackbar('Erreur', 'Vous avez déjà postulé à cette offre');
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la soumission de candidature : $e');
    }
  }

  // Fermer une offre
  Future<void> fermerOffre(Offre offre) async {
    try {
      // Mettre à jour le statut de l'offre dans Firestore
      await FirebaseFirestore.instance
          .collection('offres')
          .doc(offre.id)
          .update({'statut': 'fermee'});

      Get.snackbar('Succès', 'Offre fermée avec succès');
      await getAllOffres();  // Recharger toutes les offres
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la fermeture de l\'offre : $e');
    }
  }
}
