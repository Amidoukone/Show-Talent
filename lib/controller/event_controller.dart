import 'dart:async';

import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/events/event_repository.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class EventController extends GetxController {
  final EventRepository _eventRepository = EventRepository();

  /// Liste observable des evenements
  final Rx<List<Event>> _events = Rx<List<Event>>([]);
  List<Event> get events => _events.value;

  final RxBool _isLoading = true.obs;
  bool get isLoading => _isLoading.value;

  StreamSubscription<List<Event>>? _eventsSub;

  @override
  void onInit() {
    super.onInit();
    fetchEvents();
  }

  /// Charge les evenements depuis Firestore et met a jour le statut si expire
  Future<void> fetchEvents() async {
    _isLoading.value = true;
    await _eventsSub?.cancel();

    _eventsSub = _eventRepository.watchEvents().listen(
      (fetchedEvents) async {
        final List<Event> updatedEvents = [];

        for (final fetched in fetchedEvents) {
          var event = fetched;

          if (event.dateFin.isBefore(DateTime.now()) &&
              event.statut == 'ouvert') {
            await _eventRepository.updateEventStatus(
              eventId: event.id,
              status: 'ferm\u00e9',
            );

            event = Event(
              id: event.id,
              titre: event.titre,
              description: event.description,
              dateDebut: event.dateDebut,
              dateFin: event.dateFin,
              organisateur: event.organisateur,
              participants: event.participants,
              statut: 'ferm\u00e9',
              lieu: event.lieu,
              estPublic: event.estPublic,
              createdAt: event.createdAt,
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

        _events.value = updatedEvents
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        update();
        _isLoading.value = false;
      },
      onError: (error) {
        _isLoading.value = false;
        debugPrint('Erreur ecoute Firestore events : $error');
      },
    );
  }

  @override
  void onClose() {
    _eventsSub?.cancel();
    super.onClose();
  }

  String newEventId() => _eventRepository.newEventId();

  Future<bool> createEvent(Event event, AppUser utilisateur) async {
    if (!_isAuthorized(utilisateur)) return false;

    try {
      await _eventRepository.createEvent(event);
      _showSuccessSnackbar(
        'Evenement cree',
        'Votre evenement a ete cree avec succes.',
      );

      await _notifyPlayersOfNewEvent(event, utilisateur);
      return true;
    } catch (e) {
      _showErrorSnackbar('Erreur', 'Echec de la creation de l\'evenement.');
      debugPrint('Erreur lors de la creation de l\'evenement : $e');
      return false;
    }
  }

  Future<bool> updateEvent(Event event, AppUser utilisateur) async {
    if (!_isAuthorized(utilisateur)) return false;

    try {
      await _eventRepository.updateEvent(event);
      _showSuccessSnackbar(
        'Evenement mis a jour',
        'Les modifications ont ete enregistrees.',
      );

      return true;
    } catch (e) {
      _showErrorSnackbar('Erreur', 'Echec de la mise a jour de l\'evenement.');
      debugPrint('Erreur lors de la mise a jour de l\'evenement : $e');
      return false;
    }
  }

  Future<bool> deleteEvent(String eventId, AppUser utilisateur) async {
    if (!_isAuthorized(utilisateur)) return false;

    try {
      await _eventRepository.deleteEvent(eventId);
      _showSuccessSnackbar(
        'Evenement supprime',
        'L\'evenement a ete supprime.',
      );

      return true;
    } catch (e) {
      _showErrorSnackbar('Erreur', 'Echec de la suppression de l\'evenement.');
      debugPrint('Erreur lors de la suppression de l\'evenement : $e');
      return false;
    }
  }

  Future<void> registerToEvent(String eventId, AppUser participant) async {
    if (participant.role != 'joueur') {
      _showErrorSnackbar(
        'Acces refuse',
        'Seuls les joueurs peuvent s\'inscrire a un evenement.',
      );
      return;
    }

    try {
      final event = await _eventRepository.fetchEventById(eventId);
      if (event == null) {
        _showErrorSnackbar('Erreur', 'L\'evenement n\'existe pas.');
        return;
      }

      if (event.statut == 'ferm\u00e9' || event.statut == 'archiv\u00e9') {
        _showErrorSnackbar(
          'Inscription impossible',
          'L\'evenement n\'est pas ouvert.',
        );
        return;
      }

      if (_isAlreadyRegistered(event, participant)) {
        _showErrorSnackbar(
          'Erreur',
          'Vous etes deja inscrit a cet evenement.',
        );
        return;
      }

      final idx = _events.value.indexWhere((e) => e.id == eventId);
      if (idx != -1) {
        final local = _events.value[idx];
        local.participants.add(participant);
        _events.refresh();
      }

      final updated = [...event.participants, participant];
      await _eventRepository.updateParticipants(
        eventId: eventId,
        participants: updated,
      );

      _showSuccessSnackbar(
        'Inscription reussie',
        'Vous etes inscrit a l\'evenement.',
      );
    } catch (e) {
      _showErrorSnackbar('Erreur', 'Echec de l\'inscription.');
      debugPrint('Erreur lors de l\'inscription : $e');
    }
  }

  Future<void> unregisterFromEvent(String eventId, AppUser participant) async {
    if (participant.role != 'joueur') {
      _showErrorSnackbar(
        'Acces refuse',
        'Seuls les joueurs peuvent se desinscrire d\'un evenement.',
      );
      return;
    }

    try {
      final event = await _eventRepository.fetchEventById(eventId);
      if (event == null) {
        _showErrorSnackbar('Erreur', 'L\'evenement n\'existe pas.');
        return;
      }

      if (event.statut == 'ferm\u00e9' || event.statut == 'archiv\u00e9') {
        _showErrorSnackbar(
          'Action impossible',
          'L\'evenement n\'est plus ouvert.',
        );
        return;
      }

      if (!_isAlreadyRegistered(event, participant)) {
        _showErrorSnackbar(
          'Erreur',
          'Vous n\'etes pas inscrit a cet evenement.',
        );
        return;
      }

      final idx = _events.value.indexWhere((e) => e.id == eventId);
      if (idx != -1) {
        final local = _events.value[idx];
        local.participants.removeWhere((p) => p.uid == participant.uid);
        _events.refresh();
      }

      final updated =
          event.participants.where((p) => p.uid != participant.uid).toList();
      await _eventRepository.updateParticipants(
        eventId: eventId,
        participants: updated,
      );

      _showSuccessSnackbar(
        'Desinscription reussie',
        'Vous etes desinscrit de l\'evenement.',
      );
    } catch (e) {
      _showErrorSnackbar('Erreur', 'Echec de la desinscription.');
      debugPrint('Erreur lors de la desinscription : $e');
    }
  }

  bool _isAuthorized(AppUser utilisateur) {
    if (!utilisateur.canPublishOpportunities) {
      _showErrorSnackbar(
        'Acces refuse',
        'Seuls les clubs, recruteurs ou agents peuvent effectuer cette action.',
      );
      return false;
    }
    return true;
  }

  bool _isAlreadyRegistered(Event event, AppUser participant) {
    return event.participants.any((p) => p.uid == participant.uid);
  }

  Future<void> _notifyPlayersOfNewEvent(
    Event event,
    AppUser utilisateur,
  ) async {
    try {
      await PushNotificationService.sendEventFanout(
        eventId: event.id,
        title: 'Nouvel evenement',
        body: '${utilisateur.nom} a cree un nouvel evenement : ${event.titre}',
      );
    } catch (e) {
      debugPrint('Erreur lors de la notification des joueurs : $e');
    }
  }

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
