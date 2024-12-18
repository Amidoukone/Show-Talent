import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:show_talent/models/notification.dart';
import 'package:show_talent/models/user.dart';

class NotificationController extends GetxController {
  final Rx<List<NotificationModel>> _notifications = Rx<List<NotificationModel>>([]);
  List<NotificationModel> get notifications => _notifications.value;

  // Utilisateur courant (Firebase)
  late AppUser currentUser;

  @override
  void onInit() {
    super.onInit();
    initCurrentUser(); // Initialise l'utilisateur
  }

  // Initialisation de l'utilisateur courant à partir de Firebase et chargement des notifications
  Future<void> initCurrentUser() async {
    var firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .get();

      if (userSnapshot.exists) {
        currentUser = AppUser.fromMap(userSnapshot.data()!);
        fetchNotifications();
      } else {
        Get.snackbar('Erreur', 'Impossible de récupérer les informations utilisateur.');
      }
    } else {
      Get.snackbar('Erreur', 'Aucun utilisateur connecté.');
    }
  }

  // Récupération des notifications de l'utilisateur courant depuis Firestore
  void fetchNotifications() {
    FirebaseFirestore.instance
        .collection('notifications')
        .where('destinataire.uid', isEqualTo: currentUser.uid) // Utilisation du champ UID correct
        .orderBy('dateCreation', descending: true)
        .snapshots()
        .listen((snapshot) {
      _notifications.value = snapshot.docs
          .map((doc) => NotificationModel.fromMap(doc.data()))
          .toList();
      update(); // Mise à jour de la liste des notifications
    });
  }

  // Envoi d'une notification à un utilisateur
  Future<void> sendNotification(NotificationModel notification) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notification.id)
          .set(notification.toMap());
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de l\'envoi de la notification : $e');
    }
  }

  // Envoi de notifications à tous les utilisateurs
  Future<void> sendNotificationToAll({
    required String title,
    required String message,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();

      for (var userDoc in usersSnapshot.docs) {
        final user = AppUser.fromMap(userDoc.data());

        final notification = NotificationModel(
          id: FirebaseFirestore.instance.collection('notifications').doc().id,
          message: message,
          type: type,
          destinataire: user, // AppUser est correctement utilisé ici
          dateCreation: DateTime.now(),
          estLue: false,
        );

        await sendNotification(notification);
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible d\'envoyer les notifications : $e');
    }
  }

  // Marque une notification comme lue
  Future<void> markAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'estLue': true});
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la mise à jour de la notification : $e');
    }
  }
}
 