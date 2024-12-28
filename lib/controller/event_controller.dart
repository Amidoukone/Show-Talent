import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';

class EventController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Liste observable des événements
  final Rx<List<Event>> _events = Rx<List<Event>>([]);
  List<Event> get events => _events.value;

  @override
  void onInit() {
    super.onInit();
    fetchEvents(); // Charger les événements au démarrage
  }

  /// Charger les événements depuis Firestore
  void fetchEvents() {
    _firestore.collection('events').snapshots().listen((snapshot) {
      _events.value =
          snapshot.docs.map((doc) => Event.fromMap(doc.data())).toList();
      update(); // Mise à jour de l'interface utilisateur
    });
  }

  /// Créer un nouvel événement et notifier les joueurs
  Future<void> createEvent(Event event, AppUser utilisateur) async {
    if (!_isAuthorized(utilisateur)) return;

    try {
      await _firestore.collection('events').doc(event.id).set(event.toMap());
      Get.snackbar('Succès', 'Événement créé avec succès.');

      // Notifier les joueurs
      await _notifyPlayersOfNewEvent(event, utilisateur);

      Get.back(result: true); // Retourner à l'écran précédent
    } catch (e) {
      print('Erreur lors de la création de l\'événement : $e');
      Get.snackbar('Erreur', 'Échec de la création de l\'événement.');
    }
  }

  /// Mettre à jour un événement existant
  Future<void> updateEvent(Event event, AppUser utilisateur) async {
    if (!_isAuthorized(utilisateur)) return;

    try {
      await _firestore.collection('events').doc(event.id).update(event.toMap());
      Get.snackbar('Succès', 'Événement mis à jour avec succès.');
      Get.back(result: true); // Retourner à l'écran précédent
    } catch (e) {
      print('Erreur lors de la mise à jour de l\'événement : $e');
      Get.snackbar('Erreur', 'Échec de la mise à jour de l\'événement.');
    }
  }

  /// Supprimer un événement
  Future<void> deleteEvent(String eventId, AppUser utilisateur) async {
    if (!_isAuthorized(utilisateur)) return;

    try {
      await _firestore.collection('events').doc(eventId).delete();
      Get.snackbar('Succès', 'Événement supprimé avec succès.');
      Get.back(result: true); // Retourner à l'écran précédent
    } catch (e) {
      print('Erreur lors de la suppression de l\'événement : $e');
      Get.snackbar('Erreur', 'Échec de la suppression de l\'événement.');
    }
  }

  /// Inscrire un joueur à un événement
  Future<void> registerToEvent(String eventId, AppUser participant) async {
    if (participant.role != 'joueur') {
      Get.snackbar('Accès refusé',
          'Seuls les joueurs peuvent s\'inscrire à un événement.');
      return;
    }

    try {
      DocumentSnapshot eventDoc =
          await _firestore.collection('events').doc(eventId).get();

      if (eventDoc.exists) {
        Map<String, dynamic> eventData =
            eventDoc.data() as Map<String, dynamic>;
        Event event = Event.fromMap(eventData);

        if (!_isAlreadyRegistered(event, participant)) {
          event.participants.add(participant);
          await _firestore.collection('events').doc(eventId).update({
            'participants': event.participants.map((p) => p.toMap()).toList()
          });

          Get.snackbar('Succès', 'Inscription réussie.');
        } else {
          Get.snackbar('Erreur', 'Vous êtes déjà inscrit à cet événement.');
        }
      } else {
        Get.snackbar('Erreur', 'L\'événement n\'existe pas.');
      }
    } catch (e) {
      print('Erreur lors de l\'inscription : $e');
      Get.snackbar('Erreur', 'Échec de l\'inscription.');
    }
  }

  /// Désinscrire un joueur d'un événement
  Future<void> unregisterFromEvent(String eventId, AppUser participant) async {
    if (participant.role != 'joueur') {
      Get.snackbar('Accès refusé',
          'Seuls les joueurs peuvent se désinscrire d\'un événement.');
      return;
    }

    try {
      DocumentSnapshot eventDoc =
          await _firestore.collection('events').doc(eventId).get();

      if (eventDoc.exists) {
        Map<String, dynamic> eventData =
            eventDoc.data() as Map<String, dynamic>;
        Event event = Event.fromMap(eventData);

        if (_isAlreadyRegistered(event, participant)) {
          event.participants
              .removeWhere((participantItem) => participantItem.uid == participant.uid);
          await _firestore.collection('events').doc(eventId).update({
            'participants': event.participants.map((p) => p.toMap()).toList()
          });

          Get.snackbar('Succès', 'Désinscription réussie.');
        } else {
          Get.snackbar('Erreur', 'Vous n\'êtes pas inscrit à cet événement.');
        }
      } else {
        Get.snackbar('Erreur', 'L\'événement n\'existe pas.');
      }
    } catch (e) {
      print('Erreur lors de la désinscription : $e');
      Get.snackbar('Erreur', 'Échec de la désinscription.');
    }
  }

  /// Vérifier si un utilisateur est autorisé
  bool _isAuthorized(AppUser utilisateur) {
    if (utilisateur.role != 'recruteur' && utilisateur.role != 'club') {
      Get.snackbar('Accès refusé',
          'Seuls les clubs ou recruteurs peuvent effectuer cette action.');
      return false;
    }
    return true;
  }

  /// Vérifier si un joueur est déjà inscrit
  bool _isAlreadyRegistered(Event event, AppUser participant) {
    return event.participants.any((p) => p.uid == participant.uid);
  }

  /// Notifier les joueurs d'un nouvel événement
  Future<void> _notifyPlayersOfNewEvent(Event event, AppUser utilisateur) async {
    final joueursSnapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'joueur')
        .get();

    for (var joueurDoc in joueursSnapshot.docs) {
      final joueurData = joueurDoc.data();
      final fcmToken = joueurData['fcmToken'];

      if (fcmToken != null && fcmToken.isNotEmpty) {
        await PushNotificationService.sendNotification(
          title: 'Nouvel Événement',
          body:
              '${utilisateur.nom} a créé un nouvel événement : ${event.titre}',
          token: fcmToken,
          contextType: 'event',
          contextData: event.id,
        );
      }
    }
  }
}
