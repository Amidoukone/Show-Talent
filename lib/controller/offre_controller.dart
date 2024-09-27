
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/auth_controller.dart';
import 'package:show_talent/controller/notification_controller.dart';
import 'package:show_talent/models/notification.dart';
import 'package:show_talent/models/offre.dart';
import 'package:show_talent/models/user.dart';


class OffreController extends GetxController {
  static OffreController instance = Get.find();

  RxList<Offre> offres = <Offre>[].obs; 

  // Controller des notifications
  final NotificationController notificationController = Get.put(NotificationController());

  Future<void> getAllOffres() async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('offres').get();
    offres.value = snapshot.docs
        .map((doc) => Offre.fromMap(doc.data() as Map<String, dynamic>))
        .toList();
  }

  Future<void> publierOffre(String titre, String description, DateTime dateDebut, DateTime dateFin) async {
    String id = FirebaseFirestore.instance.collection('offres').doc().id;
    AppUser recruteur = AuthController.instance.user as AppUser;

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

    await FirebaseFirestore.instance
        .collection('offres')
        .doc(id)
        .set(newOffre.toMap());

    // Envoi d'une notification à tous les joueurs (ou utilisateurs ciblés)
    List<AppUser> joueurs = await getJoueursCibles(); // Obtenir une liste des joueurs à notifier
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

    Get.snackbar('Succès', 'Offre publiée avec succès');
    getAllOffres();
  }

  // Cette méthode pourrait récupérer tous les joueurs à notifier
  Future<List<AppUser>> getJoueursCibles() async {
    // Logique pour obtenir la liste des joueurs (par exemple, tous les joueurs enregistrés)
    QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'joueur').get();
    return snapshot.docs.map((doc) => AppUser.fromMap(doc.data() as Map<String, dynamic>)).toList();
  }

  Future<void> postulerOffre(Offre offre) async {
    AppUser joueur = AuthController.instance.user as AppUser;

    if (!offre.candidats.contains(joueur)) {
      offre.candidats.add(joueur);

      await FirebaseFirestore.instance
          .collection('offres')
          .doc(offre.id)
          .update({'candidats': offre.candidats.map((j) => j.toMap()).toList()});

      Get.snackbar('Succès', 'Vous avez postulé à l\'offre');
    } else {
      Get.snackbar('Erreur', 'Vous avez déjà postulé à cette offre');
    }
  }

  Future<void> fermerOffre(Offre offre) async {
    offre.statut = 'fermée';
    await FirebaseFirestore.instance
        .collection('offres')
        .doc(offre.id)
        .update({'statut': 'fermée'});

    Get.snackbar('Offre fermée', 'L\'offre a été fermée avec succès');
  }
}
