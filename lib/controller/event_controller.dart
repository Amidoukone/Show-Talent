import 'dart:async';

import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_diagnostics.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/events/event_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:adfoot/services/app_logger.dart';

class EventController extends GetxController {
  static const int _eventPageSize = EventRepository.defaultPageSize;

  final EventRepository _eventRepository = EventRepository();
  final AuthSessionService _authSessionService = AuthSessionService();

  final Rx<List<Event>> _events = Rx<List<Event>>([]);
  List<Event> get events => _events.value;

  final RxBool _isLoading = true.obs;
  bool get isLoading => _isLoading.value;

  final RxBool _isLoadingMore = false.obs;
  bool get isLoadingMore => _isLoadingMore.value;

  final RxBool _hasMoreEvents = false.obs;
  bool get hasMoreEvents => _hasMoreEvents.value;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<EventLiveBatch>? _eventsSub;
  EventFeedCursor? _lastCursor;
  EventQueryFilter _activeFilter = const EventQueryFilter();
  String? _activeAuthUid;
  String? _activeEventsQueryKey;
  bool _hasLoadedAdditionalPages = false;

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
      onError: (Object error) {
        // Nothing re-subscribes, so events stop following the session
        // entirely from here on. Same stream and same failure as
        // UserController's and ChatController's — one incident, one stage.
        AuthDiagnostics.failure(
          'auth state stream failed; events have stopped following the session',
          stage: 'auth_stream',
          error: error,
        );
      },
    );

    if (_authSessionService.currentUser != null) {
      fetchEvents();
    } else {
      _isLoading.value = false;
    }
  }

  Future<void> fetchEvents({
    EventQueryFilter filter = const EventQueryFilter(),
    bool forceRefresh = false,
  }) async {
    final currentUid = _authSessionService.currentUser?.uid;
    final queryKey = filter.cacheKey;
    final hasActiveStream =
        _eventsSub != null &&
        _activeAuthUid == currentUid &&
        _activeEventsQueryKey == queryKey &&
        !forceRefresh;
    if (hasActiveStream) {
      return;
    }

    _activeAuthUid = currentUid;
    _activeEventsQueryKey = queryKey;
    _activeFilter = filter;
    _lastCursor = null;
    _hasLoadedAdditionalPages = false;
    _hasMoreEvents.value = false;
    _isLoadingMore.value = false;
    if (_events.value.isEmpty) {
      _isLoading.value = true;
    }
    await _eventsSub?.cancel();

    _eventsSub = _eventRepository
        .watchEvents(limit: _eventPageSize, filter: filter)
        .listen(
          (batch) {
            final updatedEvents = _prepareEvents(batch.events);
            _lastCursor = batch.cursor;
            _hasMoreEvents.value =
                batch.cursor != null && batch.fetchedCount >= _eventPageSize;
            if (_hasLoadedAdditionalPages) {
              final mergedById = <String, Event>{
                for (final event in _events.value) event.id: event,
              };
              for (final event in updatedEvents) {
                mergedById[event.id] = event;
              }
              _events.value = _sortEvents(mergedById.values);
            } else {
              _events.value = _sortEvents(updatedEvents);
            }
            update();
            _isLoading.value = false;
          },
          onError: (Object error) {
            _isLoading.value = false;

            // Dropped because the stream is finished — a Firestore snapshot
            // subscription does not deliver again after an error — and
            // holding the dead handle is what made this unrecoverable.
            //
            // `fetchEvents` returns early while `_eventsSub` is not null for
            // the same uid and query, so every later call was a no-op: the
            // `idTokenChanges` event on each hourly token refresh, and the
            // screen asking again on its next build. The Événements tab
            // stayed on whatever it last held — usually nothing — until the
            // app was restarted.
            //
            // This is the symptom that was previously blamed on GetX
            // disposing route-scoped controllers. It was never that: these
            // controllers are permanent. It was this.
            _eventsSub = null;

            AppLogger.error(
              'events stream stopped; the tab will not refresh until it is '
              'rebound',
              source: 'events/watch',
              error: error,
            );

            if (_isPermissionDenied(error)) {
              _events.value = const <Event>[];
              final hasResolvedSession =
                  Get.isRegistered<UserController>() &&
                  Get.find<UserController>().user != null;
              if (hasResolvedSession &&
                  _authSessionService.currentUser != null) {
                unawaited(_handleProtectedAccessDenied());
              }
            }
          },
        );
  }

  Future<void> loadMoreEvents() async {
    if (_isLoadingMore.value || !_hasMoreEvents.value) {
      return;
    }

    final cursor = _lastCursor;
    if (cursor == null) {
      _hasMoreEvents.value = false;
      return;
    }

    _isLoadingMore.value = true;
    try {
      final page = await _eventRepository.fetchEventsPage(
        limit: _eventPageSize,
        startAfter: cursor,
        filter: _activeFilter,
      );
      final mergedById = <String, Event>{
        for (final event in _events.value) event.id: event,
      };
      for (final event in _prepareEvents(page.events)) {
        mergedById[event.id] = event;
      }

      _lastCursor = page.cursor;
      _hasMoreEvents.value =
          page.cursor != null && page.fetchedCount >= _eventPageSize;
      if (page.fetchedCount > 0) {
        _hasLoadedAdditionalPages = true;
      }
      _events.value = _sortEvents(mergedById.values);
      update();
    } on FirebaseException catch (error, st) {
      AppLogger.warning(
        'Firestore events pagination failed: $error',
        source: 'EventController.loadMoreEvents',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
    } catch (error, st) {
      AppLogger.warning(
        'Event pagination failed: $error',
        source: 'EventController.loadMoreEvents',
        error: error,
        stackTrace: st,
      );
    } finally {
      _isLoadingMore.value = false;
    }
  }

  Future<void> _stopEventsStream({bool clearData = false}) async {
    await _eventsSub?.cancel();
    _eventsSub = null;
    _activeAuthUid = null;
    _activeEventsQueryKey = null;
    _activeFilter = const EventQueryFilter();
    _lastCursor = null;
    _hasLoadedAdditionalPages = false;
    _hasMoreEvents.value = false;
    _isLoadingMore.value = false;

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

  /// Attache une affiche a un evenement deja cree.
  ///
  /// Deux temps, imposes par la regle de stockage : `isOwnedEventDoc` lit le
  /// document pour savoir qui televerse, donc l'evenement doit exister avant
  /// son image. L'appelant cree d'abord, attache ensuite.
  ///
  /// Un echec ici ne remet pas l'evenement en cause -- il est publie, il est
  /// visible, il lui manque une image. La reponse le dit sans faire croire que
  /// la publication a echoue.
  Future<ActionResponse> attachFlyer({
    required String eventId,
    required String filePath,
  }) async {
    try {
      final url = await _eventRepository.uploadFlyer(
        eventId: eventId,
        filePath: filePath,
      );
      await _eventRepository.setFlyerUrl(eventId: eventId, flyerUrl: url);
      return const ActionResponse(
        success: true,
        code: 'flyer_attached',
        message: 'Affiche ajoutee.',
        toast: ToastLevel.none,
      );
    } on FirebaseException catch (error, st) {
      AppLogger.warning(
        'Televersement affiche evenement echoue: $error',
        source: 'EventController.attachFlyer',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'flyer_failed',
        message: 'L’affiche n’a pas pu etre ajoutee.',
      );
    } catch (e, st) {
      AppLogger.warning(
        'Televersement affiche evenement echoue: $e',
        source: 'EventController.attachFlyer',
        error: e,
        stackTrace: st,
      );
      return ActionResponse.failure(
        code: 'flyer_failed',
        message: 'L’affiche n’a pas pu etre ajoutee.',
      );
    }
  }

  /// Retire l'affiche : le fichier, puis le champ.
  Future<ActionResponse> removeFlyer(String eventId) async {
    try {
      await _eventRepository.deleteFlyer(eventId);
      await _eventRepository.setFlyerUrl(eventId: eventId, flyerUrl: null);
      return const ActionResponse(
        success: true,
        code: 'flyer_removed',
        message: 'Affiche retiree.',
        toast: ToastLevel.none,
      );
    } catch (e, st) {
      AppLogger.warning(
        'Suppression affiche evenement echouee: $e',
        source: 'EventController.removeFlyer',
        error: e,
        stackTrace: st,
      );
      return ActionResponse.failure(
        code: 'flyer_remove_failed',
        message: 'L’affiche n’a pas pu etre retiree.',
      );
    }
  }

  /// Compte un lecteur, sans jamais faire echouer l'affichage pour autant.
  ///
  /// Le pendant exact de `OffreController.incrementVues`. Un compteur qui
  /// remonterait son echec a l'utilisateur couterait plus qu'il ne rapporte :
  /// l'evenement s'affiche, le compte se perd, et le journal le dit.
  Future<void> incrementVues({
    required Event event,
    required AppUser viewer,
  }) async {
    if (viewer.uid == event.organisateur.uid) return;

    try {
      await _eventRepository.incrementViews(event: event, viewer: viewer);
    } catch (e, st) {
      AppLogger.warning(
        'Erreur incrementation vues evenement: $e',
        source: 'EventController.incrementVues',
        error: e,
        stackTrace: st,
      );
    }
  }

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
              'Événement créé avec succès, mais les notifications sont indisponibles.',
          toast: ToastLevel.info,
        );
      }

      return const ActionResponse(
        success: true,
        code: 'created',
        message: 'Votre événement a été créé avec succès.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error, st) {
      AppLogger.warning(
        'Event creation failed: $error',
        source: 'EventController.createEvent',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'create_failed',
        message: 'Échec de la création de l’événement.',
      );
    } catch (e, st) {
      AppLogger.warning(
        'Event creation failed: $e',
        source: 'EventController.createEvent',
        error: e,
        stackTrace: st,
      );
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
      _replaceLocalEvent(event);
      return const ActionResponse(
        success: true,
        code: 'updated',
        message: 'Les modifications ont été enregistrées.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error, st) {
      AppLogger.warning(
        'Event update failed: $error',
        source: 'EventController.updateEvent',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'update_failed',
        message: 'Échec de la mise à jour de l’événement.',
      );
    } catch (e, st) {
      AppLogger.warning(
        'Event update failed: $e',
        source: 'EventController.updateEvent',
        error: e,
        stackTrace: st,
      );
      return ActionResponse.failure(
        code: 'update_failed',
        message: 'Échec de la mise à jour de l’événement.',
      );
    }
  }

  Future<ActionResponse> deleteEvent(
    String eventId,
    AppUser utilisateur,
  ) async {
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
      _removeLocalEvent(eventId);
      return const ActionResponse(
        success: true,
        code: 'deleted',
        message: 'L’événement a été supprimé.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error, st) {
      AppLogger.warning(
        'Event deletion failed: $error',
        source: 'EventController.deleteEvent',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'delete_failed',
        message: 'Échec de la suppression de l’événement.',
      );
    } catch (e, st) {
      AppLogger.warning(
        'Event deletion failed: $e',
        source: 'EventController.deleteEvent',
        error: e,
        stackTrace: st,
      );
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

    final localEvent = _findLocalEvent(eventId);
    final previousParticipants = localEvent == null
        ? null
        : List<AppUser>.from(localEvent.participants);
    if (localEvent != null) {
      _setLocalEventParticipantState(localEvent, participant, registered: true);
    }

    try {
      await _eventRepository.registerParticipant(
        eventId: eventId,
        participant: participant,
      );
      if (localEvent != null) {
        _setLocalEventParticipantState(
          localEvent,
          participant,
          registered: true,
        );
      }

      return const ActionResponse(
        success: true,
        code: 'registered',
        message: 'Vous êtes inscrit à l’événement.',
        toast: ToastLevel.success,
      );
    } on EventRepositoryException catch (e) {
      if (localEvent != null) {
        if (e.code == 'already_registered') {
          _setLocalEventParticipantState(
            localEvent,
            participant,
            registered: true,
          );
        } else if (previousParticipants != null) {
          _restoreLocalEventParticipants(localEvent, previousParticipants);
        }
      }
      return ActionResponse.failure(
        code: e.code,
        message: e.message,
        toast: ToastLevel.info,
      );
    } on FirebaseException catch (error, st) {
      if (localEvent != null && previousParticipants != null) {
        _restoreLocalEventParticipants(localEvent, previousParticipants);
      }
      AppLogger.warning(
        'Event registration failed: $error',
        source: 'EventController.registerToEvent',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'registration_failed',
        message: 'Échec de l’inscription.',
      );
    } catch (e, st) {
      if (localEvent != null && previousParticipants != null) {
        _restoreLocalEventParticipants(localEvent, previousParticipants);
      }
      AppLogger.warning(
        'Event registration failed: $e',
        source: 'EventController.registerToEvent',
        error: e,
        stackTrace: st,
      );
      return ActionResponse.failure(
        code: 'registration_failed',
        message: 'Échec de l’inscription.',
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

    final localEvent = _findLocalEvent(eventId);
    final previousParticipants = localEvent == null
        ? null
        : List<AppUser>.from(localEvent.participants);
    if (localEvent != null) {
      _setLocalEventParticipantState(
        localEvent,
        participant,
        registered: false,
      );
    }

    try {
      await _eventRepository.unregisterParticipant(
        eventId: eventId,
        participant: participant,
      );
      if (localEvent != null) {
        _setLocalEventParticipantState(
          localEvent,
          participant,
          registered: false,
        );
      }

      return const ActionResponse(
        success: true,
        code: 'unregistered',
        message: 'Vous êtes désinscrit de l’événement.',
        toast: ToastLevel.success,
      );
    } on EventRepositoryException catch (e) {
      if (localEvent != null) {
        if (e.code == 'not_registered') {
          _setLocalEventParticipantState(
            localEvent,
            participant,
            registered: false,
          );
        } else if (previousParticipants != null) {
          _restoreLocalEventParticipants(localEvent, previousParticipants);
        }
      }
      return ActionResponse.failure(
        code: e.code,
        message: e.message,
        toast: ToastLevel.info,
      );
    } on FirebaseException catch (error, st) {
      if (localEvent != null && previousParticipants != null) {
        _restoreLocalEventParticipants(localEvent, previousParticipants);
      }
      AppLogger.warning(
        'Event unregistration failed: $error',
        source: 'EventController.unregisterFromEvent',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'unregistration_failed',
        message: 'Échec de la désinscription.',
      );
    } catch (e, st) {
      if (localEvent != null && previousParticipants != null) {
        _restoreLocalEventParticipants(localEvent, previousParticipants);
      }
      AppLogger.warning(
        'Event unregistration failed: $e',
        source: 'EventController.unregisterFromEvent',
        error: e,
        stackTrace: st,
      );
      return ActionResponse.failure(
        code: 'unregistration_failed',
        message: 'Échec de la désinscription.',
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

  List<Event> _prepareEvents(Iterable<Event> fetchedEvents) {
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
                AppLogger.warning(
                  'Auto close event status update failed: $error',
                  source: 'EventController._prepareEvents',
                  error: error,
                  stackTrace: stack,
                );
              }),
        );

        event.statut = 'ferme';
        event.lastUpdated = now;
      }

      updatedEvents.add(event);
    }

    return updatedEvents;
  }

  List<Event> _sortEvents(Iterable<Event> events) {
    return events.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Event? _findLocalEvent(String eventId) {
    final index = _events.value.indexWhere((event) => event.id == eventId);
    return index == -1 ? null : _events.value[index];
  }

  void _setLocalEventParticipantState(
    Event event,
    AppUser participant, {
    required bool registered,
  }) {
    event.participants.removeWhere(
      (candidate) => candidate.uid == participant.uid,
    );
    if (registered) {
      event.participants.add(participant);
    }
    _replaceLocalEvent(event);
  }

  void _restoreLocalEventParticipants(
    Event event,
    List<AppUser> previousParticipants,
  ) {
    event.participants
      ..clear()
      ..addAll(previousParticipants);
    _replaceLocalEvent(event);
  }

  /// Remplace l'entree locale par l'evenement qui vient d'etre enregistre,
  /// sans reprendre les champs que le serveur possede.
  ///
  /// Le pendant exact de `OffreController._replaceLocalOffer`, meme raison :
  /// `updateEvent` n'envoie plus `participants`, `views` ni `viewedBy` -- voir
  /// `_serverOwnedEventFields` -- donc l'objet soumis porte l'etat d'avant
  /// l'ouverture du formulaire. `participants` etant `final`, il faut
  /// reconstruire plutot qu'assigner.
  void _replaceLocalEvent(Event event) {
    final existing = _events.value;
    final index = existing.indexWhere((candidate) => candidate.id == event.id);
    if (index == -1) {
      update();
      return;
    }

    final previous = existing[index];
    final merged = Event(
      id: event.id,
      titre: event.titre,
      description: event.description,
      dateDebut: event.dateDebut,
      dateFin: event.dateFin,
      organisateur: event.organisateur,
      participants: previous.participants,
      statut: event.statut,
      lieu: event.lieu,
      estPublic: event.estPublic,
      createdAt: event.createdAt,
      capaciteMax: event.capaciteMax,
      tags: event.tags,
      streamingUrl: event.streamingUrl,
      flyerUrl: event.flyerUrl,
      views: previous.views,
      viewedBy: previous.viewedBy,
      archivedAt: event.archivedAt,
      lastUpdated: event.lastUpdated,
    );

    final next = List<Event>.from(existing);
    next[index] = merged;
    _events.value = _sortEvents(next);
    update();
  }

  void _removeLocalEvent(String eventId) {
    final next = _events.value
        .where((event) => event.id != eventId)
        .toList(growable: false);
    if (next.length == _events.value.length) {
      return;
    }

    _events.value = next;
    update();
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
