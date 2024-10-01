import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Ajout pour l'authentification
import 'package:show_talent/models/notification.dart';

class NotificationController extends GetxController {
  final Rx<List<NotificationModel>> _notifications = Rx<List<NotificationModel>>([]);
  List<NotificationModel> get notifications => _notifications.value;

  // Utilisateur courant (récupéré à partir de Firebase)
  late User currentUser;

  @override
  void onInit() {
    super.onInit();
    initCurrentUser(); // Initialiser l'utilisateur
  }

  // Méthode pour initialiser l'utilisateur à partir de Firebase et ensuite charger les notifications
  void initCurrentUser() {
    var user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      currentUser = user;
      fetchNotifications();  // Ne charger les notifications qu'après avoir récupéré l'utilisateur
    } else {
      Get.snackbar('Erreur', 'Aucun utilisateur connecté');
    }
  }

  // Méthode pour récupérer les notifications de l'utilisateur courant depuis Firestore
  void fetchNotifications() {
    FirebaseFirestore.instance
        .collection('notifications')
        .where('destinataire.id', isEqualTo: currentUser.uid) // Utiliser l'ID Firebase
        .orderBy('dateCreation', descending: true)
        .snapshots()
        .listen((snapshot) {
      _notifications.value = snapshot.docs
          .map((doc) => NotificationModel.fromMap(doc.data()))
          .toList();
      update(); // Mise à jour des notifications
    });
  }

  // Méthode pour envoyer une notification
  Future<void> sendNotification(NotificationModel notification) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notification.id)
          .set(notification.toMap());
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de l\'envoi de la notification');
    }
  }

  // Marquer une notification comme lue
  Future<void> markAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'estLue': true});
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la mise à jour de la notification');
    }
  }
}
