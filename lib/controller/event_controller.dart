import 'package:flutter/material.dart';
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

  final RxBool _isLoading = true.obs;
  bool get isLoading => _isLoading.value;

  @override
  void onInit() {
    super.onInit();
    fetchEvents(); // Charger les événements au démarrage
  }

  /// Charger les événements depuis Firestore et mettre à jour le statut si expiré
  void fetchEvents() async {
    _isLoading.value = true;

    _firestore.collection('events').snapshots().listen((snapshot) async {
      List<Event> updatedEvents = [];

      for (var doc in snapshot.docs) {
        Event event = Event.fromMap(doc.data());

        // Vérifie si la date de fin est dépassée -> fermeture automatique
        if (event.dateFin.isBefore(DateTime.now()) && event.statut == 'ouvert') {
          await _firestore.collection('events').doc(event.id).update({
            'statut': 'fermé',
            'lastUpdated': FieldValue.serverTimestamp(),
          });

          // Reconstruction (pas de copyWith)
          event = Event(
            id: event.id,
            titre: event.titre,
            description: event.description,
            dateDebut: event.dateDebut,
            dateFin: event.dateFin,
            organisateur: event.organisateur,
            participants: event.participants,
            statut: 'fermé',
            lieu: event.lieu,
            estPublic: event.estPublic,
            createdAt: event.createdAt,

            // Champs optionnels enrichis
            capaciteMax: event.capaciteMax,
            tags: event.tags,
            streamingUrl: event.streamingUrl,
            flyerUrl: event.flyerUrl,
            views: event.views,
            archivedAt: event.archivedAt,
            lastUpdated: DateTime.now(),
          );
        }

        updatedEvents.add(event);
      }

      _events.value = updatedEvents..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      update(); // Met à jour l'interface utilisateur
      _isLoading.value = false;
    }, onError: (e) {
      // en cas d'erreur stream : on coupe le loader
      _isLoading.value = false;
      debugPrint('Erreur écoute Firestore events : $e');
    });
  }

  /// Créer un nouvel événement
  Future<void> createEvent(Event event, AppUser utilisateur) async {
    if (!_isAuthorized(utilisateur)) return;

    try {
      await _firestore.collection('events').doc(event.id).set(event.toMap());
      _showSuccessSnackbar('Événement créé', 'Votre événement a été créé avec succès.');

      await _notifyPlayersOfNewEvent(event, utilisateur);

      fetchEvents(); // Mettre à jour la liste
      Get.back(); // Fermer l'écran de création
    } catch (e) {
      _showErrorSnackbar('Erreur', 'Échec de la création de l\'événement.');
      debugPrint('Erreur lors de la création de l\'événement : $e');
    }
  }

  /// Mettre à jour un événement existant
  Future<void> updateEvent(Event event, AppUser utilisateur) async {
    if (!_isAuthorized(utilisateur)) return;

    try {
      await _firestore.collection('events').doc(event.id).update(event.toMap());
      _showSuccessSnackbar('Événement mis à jour', 'Les modifications ont été enregistrées.');

      fetchEvents(); // Rafraîchir la liste
      Get.back(); // Fermer le dialogue
    } catch (e) {
      _showErrorSnackbar('Erreur', 'Échec de la mise à jour de l\'événement.');
      debugPrint('Erreur lors de la mise à jour de l\'événement : $e');
    }
  }

  /// Supprimer un événement
  Future<void> deleteEvent(String eventId, AppUser utilisateur) async {
    if (!_isAuthorized(utilisateur)) return;

    try {
      await _firestore.collection('events').doc(eventId).delete();
      _showSuccessSnackbar('Événement supprimé', 'L\'événement a été supprimé.');

      fetchEvents(); // Rafraîchir la liste
      Get.back(); // Fermer la boîte de dialogue
    } catch (e) {
      _showErrorSnackbar('Erreur', 'Échec de la suppression de l\'événement.');
      debugPrint('Erreur lors de la suppression de l\'événement : $e');
    }
  }

  /// Inscrire un joueur à un événement
  Future<void> registerToEvent(String eventId, AppUser participant) async {
    if (participant.role != 'joueur') {
      _showErrorSnackbar('Accès refusé', 'Seuls les joueurs peuvent s\'inscrire à un événement.');
      return;
    }

    try {
      DocumentSnapshot eventDoc = await _firestore.collection('events').doc(eventId).get();

      if (!eventDoc.exists) {
        _showErrorSnackbar('Erreur', 'L\'événement n\'existe pas.');
        return;
      }

      Event event = Event.fromMap(eventDoc.data() as Map<String, dynamic>);

      if (event.statut == 'fermé' || event.statut == 'archivé') {
        _showErrorSnackbar('Inscription impossible', 'L\'événement n\'est pas ouvert.');
        return;
      }

      if (_isAlreadyRegistered(event, participant)) {
        _showErrorSnackbar('Erreur', 'Vous êtes déjà inscrit à cet événement.');
        return;
      }

      // ✅ update optimiste local (si l’UI s’appuie sur la liste observée)
      // Note: on ne connaît pas forcément l’instance référencée dans _events, donc on patch par id.
      final int idx = _events.value.indexWhere((e) => e.id == eventId);
      if (idx != -1) {
        final local = _events.value[idx];
        local.participants.add(participant);
        _events.refresh();
      }

      // ✅ write Firestore
      final updated = [...event.participants, participant];
      await _firestore.collection('events').doc(eventId).update({
        'participants': updated.map((p) => p.toMap()).toList(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      _showSuccessSnackbar('Inscription réussie', 'Vous êtes inscrit à l\'événement.');
    } catch (e) {
      _showErrorSnackbar('Erreur', 'Échec de l\'inscription.');
      debugPrint('Erreur lors de l\'inscription : $e');
    }
  }

  /// Désinscrire un joueur d'un événement
  Future<void> unregisterFromEvent(String eventId, AppUser participant) async {
    if (participant.role != 'joueur') {
      _showErrorSnackbar(
        'Accès refusé',
        'Seuls les joueurs peuvent se désinscrire d\'un événement.',
      );
      return;
    }

    try {
      DocumentSnapshot eventDoc = await _firestore.collection('events').doc(eventId).get();

      if (!eventDoc.exists) {
        _showErrorSnackbar('Erreur', 'L\'événement n\'existe pas.');
        return;
      }

      Event event = Event.fromMap(eventDoc.data() as Map<String, dynamic>);

      if (event.statut == 'fermé' || event.statut == 'archivé') {
        _showErrorSnackbar('Action impossible', 'L\'événement n\'est plus ouvert.');
        return;
      }

      if (!_isAlreadyRegistered(event, participant)) {
        _showErrorSnackbar('Erreur', 'Vous n\'êtes pas inscrit à cet événement.');
        return;
      }

      // ✅ update optimiste local
      final int idx = _events.value.indexWhere((e) => e.id == eventId);
      if (idx != -1) {
        final local = _events.value[idx];
        local.participants.removeWhere((p) => p.uid == participant.uid);
        _events.refresh();
      }

      // ✅ write Firestore
      final updated = event.participants.where((p) => p.uid != participant.uid).toList();
      await _firestore.collection('events').doc(eventId).update({
        'participants': updated.map((p) => p.toMap()).toList(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      _showSuccessSnackbar('Désinscription réussie', 'Vous êtes désinscrit de l\'événement.');
    } catch (e) {
      _showErrorSnackbar('Erreur', 'Échec de la désinscription.');
      debugPrint('Erreur lors de la désinscription : $e');
    }
  }

  /// Vérifier si un utilisateur est autorisé
  bool _isAuthorized(AppUser utilisateur) {
    if (utilisateur.role != 'recruteur' && utilisateur.role != 'club') {
      _showErrorSnackbar(
        'Accès refusé',
        'Seuls les clubs ou recruteurs peuvent effectuer cette action.',
      );
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
    try {
      final joueursSnapshot =
          await _firestore.collection('users').where('role', isEqualTo: 'joueur').get();

      for (var joueurDoc in joueursSnapshot.docs) {
        final joueurData = joueurDoc.data();
        final fcmToken = joueurData['fcmToken'];

        if (fcmToken != null && fcmToken.isNotEmpty) {
          await PushNotificationService.sendNotification(
            title: 'Nouvel Événement',
            body: '${utilisateur.nom} a créé un nouvel événement : ${event.titre}',
            token: fcmToken,
            contextType: 'event',
            contextData: event.id,
          );
        }
      }
    } catch (e) {
      debugPrint('Erreur lors de la notification des joueurs : $e');
    }
  }

  /// Afficher une notification de succès
  void _showSuccessSnackbar(String title, String message) {
    Get.snackbar(
      title,
      message,
      icon: const Icon(Icons.check_circle, color: Colors.green),
      backgroundColor: Colors.green.shade100,
      colorText: Colors.black87,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  /// Afficher une notification d'erreur
  void _showErrorSnackbar(String title, String message) {
    Get.snackbar(
      title,
      message,
      icon: const Icon(Icons.error, color: Colors.red),
      backgroundColor: Colors.red.shade100,
      colorText: Colors.black87,
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}
