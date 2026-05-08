import 'dart:async';

import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/events/event_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class EventController extends GetxController {
  final EventRepository _eventRepository = EventRepository();
  final AuthSessionService _authSessionService = AuthSessionService();

  final Rx<List<Event>> _events = Rx<List<Event>>([]);
  List<Event> get events => _events.value;

  final RxBool _isLoading = true.obs;
  bool get isLoading => _isLoading.value;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<Event>>? _eventsSub;
  String? _activeAuthUid;

  bool _isPermissionDenied(Object error) =>
      error is FirebaseException && error.code == 'permission-denied';

  Future<void> _handleProtectedAccessDenied() async {
    if (!Get.isRegistered<UserController>()) {
      return;
    }

    await Get.find<UserController>().handleProtectedAccessDenied(
      fallbackTitle: 'Accès indisponible',
      fallbackMessage:
          'Votre session a été fermée pour protéger votre compte. Veuillez vous reconnecter.',
    );
  }

  ActionResponse _sessionRevokedResponse() {
    return const ActionResponse(
      success: false,
      code: 'session_revoked',
      message: 'Votre session a été fermée. Veuillez vous reconnecter.',
      toast: ToastLevel.none,
    );
  }

  @override
  void onInit() {
    super.onInit();
    _authSub = _authSessionService.idTokenChanges().listen(
      (user) {
        if (user == null) {
          unawaited(_stopEventsStream(clearData: true));
          return;
        }

        fetchEvents();
      },
      onError: (error) {
        debugPrint('EventController auth listen error: $error');
      },
    );

    if (_authSessionService.currentUser != null) {
      fetchEvents();
    } else {
      _isLoading.value = false;
    }
  }

  Future<void> fetchEvents() async {
    final currentUid = _authSessionService.currentUser?.uid;
    final hasActiveStream =
        _eventsSub != null && _activeAuthUid == currentUid;
    if (hasActiveStream) {
      return;
    }

    _activeAuthUid = currentUid;
    if (_events.value.isEmpty) {
      _isLoading.value = true;
    }
    await _eventsSub?.cancel();

    _eventsSub = _eventRepository.watchEvents().listen(
      (fetchedEvents) {
        final now = DateTime.now();
        final updatedEvents = <Event>[];

        for (final event in fetchedEvents) {
          final normalizedStatus = Event.normalizeStatus(event.statut);
          if (event.statut != normalizedStatus) {
            event.statut = normalizedStatus;
          }

          if (event.dateFin.isBefore(now) && normalizedStatus == 'ouvert') {
            unawaited(
              _eventRepository
                  .updateEventStatus(eventId: event.id, status: 'ferme')
                  .catchError((error, stack) {
                debugPrint('Auto close event status update failed: $error');
              }),
            );

            event.statut = 'ferme';
            event.lastUpdated = now;
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
        debugPrint('Firestore events stream failed: $error');
        if (_isPermissionDenied(error)) {
          _events.value = const <Event>[];
          final hasResolvedSession = Get.isRegistered<UserController>() &&
              Get.find<UserController>().user != null;
          if (hasResolvedSession && _authSessionService.currentUser != null) {
            unawaited(_handleProtectedAccessDenied());
          }
        }
      },
    );
  }

  Future<void> _stopEventsStream({bool clearData = false}) async {
    await _eventsSub?.cancel();
    _eventsSub = null;
    _activeAuthUid = null;

    if (clearData) {
      _events.value = const <Event>[];
      _isLoading.value = false;
      update();
    }
  }

  @override
  void onClose() {
    _authSub?.cancel();
    _eventsSub?.cancel();
    super.onClose();
  }

  String newEventId() => _eventRepository.newEventId();

  Future<ActionResponse> createEvent(Event event, AppUser utilisateur) async {
    final auth = _assertPublisherAuthorized(utilisateur);
    if (auth != null) return auth;

    try {
      final payload = Event(
        id: event.id,
        titre: event.titre,
        description: event.description,
        dateDebut: event.dateDebut,
        dateFin: event.dateFin,
        organisateur: event.organisateur,
        participants: event.participants,
        statut: Event.normalizeStatus(event.statut),
        lieu: event.lieu,
        estPublic: event.estPublic,
        createdAt: event.createdAt,
        capaciteMax: event.capaciteMax,
        tags: event.tags,
        streamingUrl: event.streamingUrl,
        flyerUrl: event.flyerUrl,
        views: event.views,
        archivedAt: event.archivedAt,
        lastUpdated: event.lastUpdated,
      );

      await _eventRepository.createEvent(payload);

      final fanout = await _notifyPlayersOfNewEvent(payload, utilisateur);
      if (!fanout.success) {
        return ActionResponse(
          success: true,
          code: 'created_notification_failed',
          message:
              'Evenement cree avec succes, mais les notifications sont indisponibles.',
          toast: ToastLevel.info,
        );
      }

      return const ActionResponse(
        success: true,
        code: 'created',
        message: 'Votre événement a été créé avec succès.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error) {
      debugPrint('Event creation failed: $error');
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'create_failed',
        message: 'Échec de la création de l’événement.',
      );
    } catch (e) {
      debugPrint('Event creation failed: $e');
      return ActionResponse.failure(
        code: 'create_failed',
        message: 'Échec de la création de l’événement.',
      );
    }
  }

  Future<ActionResponse> updateEvent(Event event, AppUser utilisateur) async {
    final auth = _assertPublisherAuthorized(utilisateur);
    if (auth != null) return auth;

    if (utilisateur.uid != event.organisateur.uid) {
      return ActionResponse.failure(
        code: 'permission-denied',
        message: 'Vous ne pouvez modifier que vos propres événements.',
        toast: ToastLevel.info,
      );
    }

    try {
      await _eventRepository.updateEvent(event);
      return const ActionResponse(
        success: true,
        code: 'updated',
        message: 'Les modifications ont ete enregistrees.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error) {
      debugPrint('Event update failed: $error');
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'update_failed',
        message: 'Échec de la mise à jour de l’événement.',
      );
    } catch (e) {
      debugPrint('Event update failed: $e');
      return ActionResponse.failure(
        code: 'update_failed',
        message: 'Échec de la mise à jour de l’événement.',
      );
    }
  }

  Future<ActionResponse> deleteEvent(
      String eventId, AppUser utilisateur) async {
    final auth = _assertPublisherAuthorized(utilisateur);
    if (auth != null) return auth;

    try {
      final event = await _eventRepository.fetchEventById(eventId);
      if (event == null) {
        return ActionResponse.failure(
          code: 'not-found',
          message: 'L’événement n’existe pas.',
          toast: ToastLevel.info,
        );
      }

      if (event.organisateur.uid != utilisateur.uid) {
        return ActionResponse.failure(
          code: 'permission-denied',
          message: 'Vous ne pouvez supprimer que vos propres événements.',
          toast: ToastLevel.info,
        );
      }

      await _eventRepository.deleteEvent(eventId);
      return const ActionResponse(
        success: true,
        code: 'deleted',
        message: 'L’événement a été supprimé.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error) {
      debugPrint('Event deletion failed: $error');
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'delete_failed',
        message: 'Échec de la suppression de l’événement.',
      );
    } catch (e) {
      debugPrint('Event deletion failed: $e');
      return ActionResponse.failure(
        code: 'delete_failed',
        message: 'Échec de la suppression de l’événement.',
      );
    }
  }

  Future<ActionResponse> registerToEvent(
    String eventId,
    AppUser participant,
  ) async {
    if (participant.role != 'joueur') {
      return ActionResponse.failure(
        code: 'permission-denied',
        message: 'Seuls les joueurs peuvent s’inscrire à un événement.',
        toast: ToastLevel.info,
      );
    }

    try {
      await _eventRepository.registerParticipant(
        eventId: eventId,
        participant: participant,
      );

      final idx = _events.value.indexWhere((e) => e.id == eventId);
      if (idx != -1) {
        final local = _events.value[idx];
        if (!local.participants.any((p) => p.uid == participant.uid)) {
          local.participants.add(participant);
          _events.refresh();
        }
      }

      return const ActionResponse(
        success: true,
        code: 'registered',
        message: 'Vous êtes inscrit à l’événement.',
        toast: ToastLevel.success,
      );
    } on EventRepositoryException catch (e) {
      return ActionResponse.failure(
        code: e.code,
        message: e.message,
        toast: ToastLevel.info,
      );
    } on FirebaseException catch (error) {
      debugPrint('Event registration failed: $error');
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'registration_failed',
        message: 'Echec de l inscription.',
      );
    } catch (e) {
      debugPrint('Event registration failed: $e');
      return ActionResponse.failure(
        code: 'registration_failed',
        message: 'Echec de l inscription.',
      );
    }
  }

  Future<ActionResponse> unregisterFromEvent(
    String eventId,
    AppUser participant,
  ) async {
    if (participant.role != 'joueur') {
      return ActionResponse.failure(
        code: 'permission-denied',
        message: 'Seuls les joueurs peuvent se désinscrire d’un événement.',
        toast: ToastLevel.info,
      );
    }

    try {
      await _eventRepository.unregisterParticipant(
        eventId: eventId,
        participant: participant,
      );

      final idx = _events.value.indexWhere((e) => e.id == eventId);
      if (idx != -1) {
        final local = _events.value[idx];
        local.participants.removeWhere((p) => p.uid == participant.uid);
        _events.refresh();
      }

      return const ActionResponse(
        success: true,
        code: 'unregistered',
        message: 'Vous êtes désinscrit de l’événement.',
        toast: ToastLevel.success,
      );
    } on EventRepositoryException catch (e) {
      return ActionResponse.failure(
        code: e.code,
        message: e.message,
        toast: ToastLevel.info,
      );
    } on FirebaseException catch (error) {
      debugPrint('Event unregistration failed: $error');
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'unregistration_failed',
        message: 'Echec de la desinscription.',
      );
    } catch (e) {
      debugPrint('Event unregistration failed: $e');
      return ActionResponse.failure(
        code: 'unregistration_failed',
        message: 'Echec de la desinscription.',
      );
    }
  }

  ActionResponse? _assertPublisherAuthorized(AppUser utilisateur) {
    if (!utilisateur.canPublishOpportunities) {
      return ActionResponse.failure(
        code: 'permission-denied',
        message:
            'Seuls les clubs, recruteurs ou agents peuvent effectuer cette action.',
        toast: ToastLevel.info,
      );
    }
    return null;
  }

  Future<ActionResponse> _notifyPlayersOfNewEvent(
    Event event,
    AppUser utilisateur,
  ) {
    return PushNotificationService.sendEventFanout(
      eventId: event.id,
      title: 'Nouvel événement',
      body: '${utilisateur.nom} a créé un nouvel événement : ${event.titre}',
    );
  }
}
