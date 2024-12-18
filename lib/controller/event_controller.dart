import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/controller/push_notification.dart';
import 'package:show_talent/models/event.dart';
import 'package:show_talent/models/user.dart';

class EventController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Rx<List<Event>> _events = Rx<List<Event>>([]);
  List<Event> get events => _events.value;

  @override
  void onInit() {
    super.onInit();
    _fetchEvents();
  }

  /// Récupérer les événements depuis Firestore
  void _fetchEvents() {
    _firestore.collection('events').snapshots().listen((snapshot) {
      _events.value = snapshot.docs.map((doc) => Event.fromMap(doc.data())).toList();
      update(); // Mise à jour de l'interface utilisateur
    });
  }

  /// Créer un nouvel événement et notifier les joueurs
  Future<void> createEvent(Event event, AppUser utilisateur) async {
    if (utilisateur.role != 'recruteur' && utilisateur.role != 'club') {
      Get.snackbar('Accès refusé', 'Seuls les clubs ou recruteurs peuvent créer des événements.');
      return;
    }

    try {
      // Ajouter l'événement dans Firestore
      await _firestore.collection('events').doc(event.id).set(event.toMap());
      Get.snackbar('Succès', 'Événement créé avec succès.');

      // Récupérer les joueurs pour leur envoyer une notification
      final joueursSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'joueur')
          .get();

      for (var joueurDoc in joueursSnapshot.docs) {
        final joueurData = joueurDoc.data();
        final fcmToken = joueurData['fcmToken'];

        if (fcmToken != null && fcmToken.isNotEmpty) {
          // Envoyer une notification push à chaque joueur
          await PushNotificationService.sendNotification(
            title: 'Nouvel Événement',
            body: '${utilisateur.nom} a créé un nouvel événement : ${event.titre}',
            token: fcmToken,
            contextType: 'event',
            contextData: event.id,
          );
          print('Notification envoyée au joueur : ${joueurData['nom']}');
        } else {
          print('Token FCM manquant pour le joueur : ${joueurData['nom']}');
        }
      }
    } catch (e) {
      print('Erreur lors de la création de l\'événement : $e');
      Get.snackbar('Erreur', 'Échec de la création de l\'événement : $e');
    }
  }

  /// Mettre à jour un événement
  Future<void> updateEvent(Event event, AppUser utilisateur) async {
    if (utilisateur.role != 'recruteur' && utilisateur.role != 'club') {
      Get.snackbar('Accès refusé', 'Seuls les clubs ou recruteurs peuvent modifier des événements.');
      return;
    }

    try {
      await _firestore.collection('events').doc(event.id).update(event.toMap());
      Get.snackbar('Succès', 'Événement mis à jour avec succès.');
    } catch (e) {
      print('Erreur lors de la mise à jour de l\'événement : $e');
      Get.snackbar('Erreur', 'Échec de la mise à jour de l\'événement : $e');
    }
  }

  /// Supprimer un événement
  Future<void> deleteEvent(String eventId, AppUser utilisateur) async {
    if (utilisateur.role != 'recruteur' && utilisateur.role != 'club') {
      Get.snackbar('Accès refusé', 'Seuls les clubs ou recruteurs peuvent supprimer des événements.');
      return;
    }

    try {
      await _firestore.collection('events').doc(eventId).delete();
      Get.snackbar('Succès', 'Événement supprimé avec succès.');
    } catch (e) {
      print('Erreur lors de la suppression de l\'événement : $e');
      Get.snackbar('Erreur', 'Échec de la suppression de l\'événement : $e');
    }
  }

  /// Inscrire un joueur à un événement
  Future<void> registerToEvent(String eventId, AppUser participant) async {
    if (participant.role != 'joueur') {
      Get.snackbar('Accès refusé', 'Seuls les joueurs peuvent s\'inscrire à un événement.');
      return;
    }

    try {
      // Récupérer l'événement depuis Firestore
      DocumentSnapshot eventDoc = await _firestore.collection('events').doc(eventId).get();

      if (eventDoc.exists) {
        Map<String, dynamic> eventData = eventDoc.data() as Map<String, dynamic>;
        Event event = Event.fromMap(eventData);

        // Vérifier si le joueur est déjà inscrit
        bool alreadyRegistered = event.participants.any((p) => p.uid == participant.uid);

        if (!alreadyRegistered) {
          // Ajouter le joueur et mettre à jour Firestore
          event.participants.add(participant);
          await _firestore
              .collection('events')
              .doc(eventId)
              .update({'participants': event.participants.map((p) => p.toMap()).toList()});

          Get.snackbar('Succès', 'Inscription réussie.');
        } else {
          Get.snackbar('Erreur', 'Vous êtes déjà inscrit à cet événement.');
        }
      } else {
        Get.snackbar('Erreur', 'L\'événement n\'existe pas.');
      }
    } catch (e) {
      print('Erreur lors de l\'inscription : $e');
      Get.snackbar('Erreur', 'Échec de l\'inscription : $e');
    }
  }

  /// Désinscrire un joueur d'un événement
  Future<void> unregisterFromEvent(String eventId, AppUser participant) async {
    if (participant.role != 'joueur') {
      Get.snackbar('Accès refusé', 'Seuls les joueurs peuvent se désinscrire d\'un événement.');
      return;
    }

    try {
      // Récupérer l'événement depuis Firestore
      DocumentSnapshot eventDoc = await _firestore.collection('events').doc(eventId).get();

      if (eventDoc.exists) {
        Map<String, dynamic> eventData = eventDoc.data() as Map<String, dynamic>;
        Event event = Event.fromMap(eventData);

        // Vérifier si le joueur est inscrit
        bool isRegistered = event.participants.any((p) => p.uid == participant.uid);

        if (isRegistered) {
          // Retirer le joueur et mettre à jour Firestore
          event.participants.removeWhere((p) => p.uid == participant.uid);
          await _firestore
              .collection('events')
              .doc(eventId)
              .update({'participants': event.participants.map((p) => p.toMap()).toList()});

          Get.snackbar('Succès', 'Désinscription réussie.');
        } else {
          Get.snackbar('Erreur', 'Vous n\'êtes pas inscrit à cet événement.');
        }
      } else {
        Get.snackbar('Erreur', 'L\'événement n\'existe pas.');
      }
    } catch (e) {
      print('Erreur lors de la désinscription : $e');
      Get.snackbar('Erreur', 'Échec de la désinscription : $e');
    }
  }
}
