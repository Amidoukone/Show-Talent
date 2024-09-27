
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/models/notification.dart';
import 'package:show_talent/models/user.dart';



class NotificationController extends GetxController {
  final Rx<List<NotificationModel>> _notifications = Rx<List<NotificationModel>>([]);
  List<NotificationModel> get notifications => _notifications.value;

  // Utilisateur courant (à initialiser après la connexion)
  late AppUser currentUser;

  @override
  void onInit() {
    super.onInit();
    fetchNotifications();
  }

  // Méthode pour récupérer les notifications de l'utilisateur courant depuis Firestore
  void fetchNotifications() {
    FirebaseFirestore.instance
        .collection('notifications')
        .where('destinataire.id', isEqualTo: currentUser.uid)
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
