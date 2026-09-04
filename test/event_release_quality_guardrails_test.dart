import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Event release quality guardrails', () {
    test('event form awaits controller result before system feedback', () {
      final form = File(
        'lib/screens/event_form_screen.dart',
      ).readAsStringSync();

      expect(form, contains('Future<void> _handleSubmit() async'));
      expect(form, contains('await eventController.updateEvent'));
      expect(form, contains('await eventController.createEvent'));
      expect(form, contains('if (!response.success)'));
      expect(form, contains('AdFeedback.error('));
      expect(form, isNot(contains('AdFeedback.success(')));
      expect(form, contains('class EventFormResult'));
      expect(form, contains('PopScope<void>'));
      expect(form, contains('_handleBackNavigation()'));
      expect(form, contains('AdDialogs.confirm('));
      expect(form, contains('bool get _submitLocked'));
      expect(form, contains('bool get _hasUnsavedChanges'));
      expect(form, contains('id: _draftEventId'));
      // Le message rendu vient toujours du controleur ; il porte en plus la
      // suite du sort de l'affiche, qui peut echouer seule.
      expect(form, contains(r"_completeSubmit('" r"$" r"{response.message}" r"$" r"flyerNote')"));
      expect(form, contains('_buildFormSection('));
      expect(
        form,
        contains('constraints: const BoxConstraints(maxWidth: 720)'),
      );
      expect(form, contains('width: double.infinity'));
      expect(form, contains('_setStartDate'));
      expect(form, contains('_setEndDate'));
      expect(form, contains("child: Text('Fermé')"));
      expect(form, contains("child: Text('Archivé')"));
      expect(form, contains('Publier l’événement'));
      expect(form, contains('maxLength: _maxTitleLength'));
      expect(form, contains('maxLength: _maxDescriptionLength'));
      expect(form, contains("locale: const Locale('fr', 'FR')"));
      expect(form, contains("DateFormat('dd MMM yyyy', 'fr_FR')"));
      expect(form, isNot(contains('streamingController')));
      expect(form, isNot(contains('flyerController')));
      expect(form, isNot(contains('Lien streaming')));
      expect(form, isNot(contains('Lien visuel')));
      expect(form, contains('streamingUrl: null'));
      // La creation n'ecrit pas d'affiche : la regle de stockage lit le
      // document pour savoir qui televerse, donc le document doit exister
      // avant son image. L'affiche est attachee juste apres, par
      // `_applyFlyerChange`.
      expect(form, contains('flyerUrl: null'));
      expect(form, contains('_applyFlyerChange(_draftEventId)'));

      // L'edition, elle, doit reconduire l'affiche existante. Sans cette
      // ligne le formulaire envoyait null a chaque fois et `updateEvent`
      // supprimait le champ : editer un evenement effacait son affiche, sans
      // que rien ne le dise.
      expect(form, contains('flyerUrl: _visibleFlyerUrl'));
      expect(form, contains('_applyFlyerChange(widget.event!.id)'));
    });

    test(
      'event list reacts to action responses for register/unregister/delete',
      () {
        final screen = File(
          'lib/screens/event_list_screen.dart',
        ).readAsStringSync();

        expect(screen, contains('await _runEventAction('));
        expect(screen, contains('eventController.registerToEvent('));
        expect(screen, contains('eventController.unregisterFromEvent('));
        expect(screen, contains('eventController.deleteEvent('));
        expect(screen, contains('Event.normalizeStatus'));
        expect(screen, contains('void _showResponse('));
        expect(screen, contains('required String successTitle'));
        expect(screen, contains('if (response.success)'));
        expect(
          screen,
          contains("import 'package:adfoot/widgets/ad_system_notice.dart';"),
        );
        expect(screen, contains('AdSystemNotice('));
        expect(screen, contains('_pendingEventActions'));
        expect(screen, contains('_isEventActionPending('));
        expect(screen, contains('_isOpenForRegistration(Event event)'));
        expect(screen, isNot(contains('_buildEventsOverview(')));
        expect(screen, contains('_onlyMine'));
        expect(screen, contains('eventController.hasMoreEvents'));
        expect(screen, contains('eventController.isLoadingMore'));
        expect(screen, contains('_buildLoadMoreFooter()'));
        expect(screen, contains('eventController.loadMoreEvents()'));
        expect(screen, contains('event.organisateur.nom.toLowerCase()'));
        expect(screen, contains('Créer un événement'));
        expect(screen, contains("hintText: 'Rechercher un événement...'"));
        expect(
          screen,
          contains('constraints: const BoxConstraints(maxWidth: 760)'),
        );
        expect(screen, contains('MaterialTapTargetSize.shrinkWrap'));
        expect(screen, contains('VisualDensity.compact'));
        expect(screen, contains('labelPadding: const EdgeInsets.symmetric'));
        expect(screen, isNot(contains('class _EventMetric')));
        expect(screen, contains('return Wrap('));
        expect(screen, contains('filteredOut: true'));
        expect(screen, contains('_resetFilters()'));
        expect(screen, contains('_openEditEventForm(event)'));
        expect(screen, contains('final isFull = _isFull(event);'));
        expect(screen, contains('S’inscrire'));
        expect(screen, isNot(contains('AdFeedback.success(')));
        expect(screen, isNot(contains("const Text('Details')")));
        expect(
          screen,
          contains('..sort((a, b) => b.createdAt.compareTo(a.createdAt))'),
        );
        expect(screen, contains('streamingUrl: null'));
        // Le menu de statut reconduit une affiche existante. Il reconstruit un
        // Event complet pour `updateEvent`, qui supprime le champ quand il
        // vaut null : un `flyerUrl: null` ici effacerait l'affiche a chaque
        // changement de statut, comme le formulaire le faisait avant 61e2e54.
        expect(screen, contains('flyerUrl: event.flyerUrl'));
        expect(screen, contains('viewedBy: event.viewedBy'));
        expect(screen, isNot(contains('flyerUrl: null')));
      },
    );

    test(
      'event controller and repository keep explicit failures and transactions',
      () {
        final controller = File(
          'lib/controller/event_controller.dart',
        ).readAsStringSync();
        final repository = File(
          'lib/services/events/event_repository.dart',
        ).readAsStringSync();

        expect(controller, contains('Future<ActionResponse> createEvent'));
        expect(controller, contains('Future<ActionResponse> updateEvent'));
        expect(controller, contains('Future<ActionResponse> deleteEvent'));
        expect(controller, contains('Future<ActionResponse> registerToEvent'));
        expect(
          controller,
          contains('Future<ActionResponse> unregisterFromEvent'),
        );
        expect(controller, contains('_assertPublisherAuthorized'));
        expect(controller, contains('sendEventFanout'));
        expect(controller, contains('_setLocalEventParticipantState'));
        expect(controller, contains('_restoreLocalEventParticipants'));
        expect(controller, contains('_findLocalEvent'));
        expect(controller, contains('previousParticipants'));
        expect(controller, contains("e.code == 'already_registered'"));
        expect(controller, contains("e.code == 'not_registered'"));

        expect(repository, contains('class EventRepositoryException'));
        expect(repository, contains('class EventFeedCursor'));
        expect(repository, contains('class EventQueryFilter'));
        expect(repository, contains('Stream<EventLiveBatch> watchEvents'));
        expect(repository, contains('Future<EventFeedPage> fetchEventsPage'));
        expect(repository, contains(".orderBy('createdAt', descending: true)"));
        expect(repository, contains('.limit(limit)'));
        expect(repository, contains('startAfterDocument'));
        expect(repository, contains("'statut'"));
        expect(repository, contains("'dateFin'"));
        expect(repository, contains('runTransaction'));
        expect(repository, contains('capacity_reached'));
        expect(repository, contains('already_registered'));
        expect(repository, contains('not_registered'));
        expect(repository, contains('event_closed'));
        expect(
          repository,
          contains("payload['streamingUrl'] = FieldValue.delete()"),
        );
        expect(
          repository,
          contains("payload['flyerUrl'] = FieldValue.delete()"),
        );
        expect(controller, contains('StreamSubscription<EventLiveBatch>'));
        expect(controller, contains('Future<void> loadMoreEvents()'));
        expect(controller, contains('_lastCursor'));
        expect(controller, contains('_eventPageSize'));
        expect(controller, contains('_replaceLocalEvent(event)'));
        expect(controller, contains('_removeLocalEvent(eventId)'));
        expect(controller, contains('fetchEventsPage('));
      },
    );

    test('event indexes support ordered and filtered production queries', () {
      final indexes = File('firestore.indexes.json').readAsStringSync();

      expect(indexes, contains('"collectionGroup": "events"'));
      expect(indexes, contains('"fieldPath": "statut"'));
      expect(indexes, contains('"fieldPath": "dateFin"'));
      expect(indexes, contains('"fieldPath": "createdAt"'));
      expect(indexes, contains('"order": "DESCENDING"'));
    });

    test(
      'event details stay in-app and tolerate transient missing session',
      () {
        final details = File(
          'lib/screens/event_detail_screen.dart',
        ).readAsStringSync();

        expect(details, contains('final AppUser? currentUser'));
        expect(details, contains('currentUser != null &&'));
        expect(
          details,
          contains('await Get.find<EventController>().fetchEvents();'),
        );
        expect(details, contains('Get.back(result: updated);'));
        expect(details, contains('current.uid == other.uid'));
        expect(details, contains('Aucun participant pour le moment.'));
        expect(details, isNot(contains('Get.find<UserController>().user!')));
        expect(details, isNot(contains('Get.offAllNamed(AppRoutes.main')));
      },
    );

    // 61e2e54 a livre l'affiche et le compteur de vues, et ne les a cables que
    // sur la carte de la liste. La fiche est pourtant l'ecran ou l'on decide de
    // participer, et celui que l'organisateur ouvre pour suivre son audience :
    // les deux y manquaient sans que rien ne le signale.
    test('the event sheet shows the flyer and the view count', () {
      final details = File(
        'lib/screens/event_detail_screen.dart',
      ).readAsStringSync();

      expect(details, contains("(currentEvent.flyerUrl ?? '').trim()"));
      expect(details, contains('Widget _buildFlyer(String url)'));
      expect(details, contains('aspectRatio: 16 / 9'));

      // `Image.network` est admis la ou `NetworkImage` ne l'est pas, mais
      // seulement parce qu'il porte un `errorBuilder` : sans lui, une affiche
      // supprimee remonte en FlutterError et serait comptée comme un incident.
      expect(details, contains('errorBuilder:'));

      expect(details, contains("label: 'Vues'"));
      expect(details, contains(r"value: '${currentEvent.views ?? 0}'"));
    });
  });
}
