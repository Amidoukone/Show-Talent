import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/models/event.dart';
import 'package:show_talent/models/user.dart';


class EventController extends GetxController {
  final Rx<List<Event>> _events = Rx<List<Event>>([]);
  List<Event> get events => _events.value;

  @override
  void onInit() {
    super.onInit();
    _fetchEvents();
  }

  // Récupération de la liste des événements depuis Firestore
  void _fetchEvents() {
    FirebaseFirestore.instance.collection('events').snapshots().listen((snapshot) {
      _events.value = snapshot.docs.map((doc) => Event.fromMap(doc.data())).toList();
      update();
    });
  }

  // Méthode pour créer un nouvel événement
  Future<void> createEvent(Event event) async {
    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .set(event.toMap());

      Get.snackbar('Succès', 'Événement créé avec succès');
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la création de l\'événement');
    }
  }

  // Méthode pour s'inscrire à un événement
  Future<void> registerToEvent(String eventId, AppUser participant) async {
    try {
      DocumentSnapshot eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .get();

      if (eventDoc.exists) {
        Event event = Event.fromMap(eventDoc.data() as Map<String, dynamic>);
        if (!event.participants.contains(participant)) {
          event.participants.add(participant);
          await FirebaseFirestore.instance
              .collection('events')
              .doc(eventId)
              .update({'participants': event.participants.map((p) => p.toMap()).toList()});
          Get.snackbar('Succès', 'Inscription réussie');
        } else {
          Get.snackbar('Erreur', 'Vous êtes déjà inscrit à cet événement');
        }
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de l\'inscription à l\'événement');
    }
  }

  // Méthode pour notifier les utilisateurs des événements à venir
  Future<void> notifyUpcomingEvents() async {
    try {
      List<Event> upcomingEvents = _events.value.where((event) {
        return event.dateDebut.isAfter(DateTime.now());
      }).toList();

      for (Event event in upcomingEvents) {
        // Envoyer des notifications automatiques aux utilisateurs ici
        // Exemple d'intégration avec un service de notification
      }
      Get.snackbar('Notifications', 'Notifications envoyées pour les événements à venir');
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de l\'envoi des notifications');
    }
  }
}