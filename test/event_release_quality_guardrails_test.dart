import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Event release quality guardrails', () {
    test('event form awaits controller result before system feedback', () {
      final form =
          File('lib/screens/event_form_screen.dart').readAsStringSync();

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
      expect(form, contains('_completeSubmit(response.message)'));
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
      expect(form, contains('_validateOptionalUrl'));
    });

    test('event list reacts to action responses for register/unregister/delete',
        () {
      final screen =
          File('lib/screens/event_list_screen.dart').readAsStringSync();

      expect(screen, contains('await _runEventAction('));
      expect(screen, contains('eventController.registerToEvent('));
      expect(screen, contains('eventController.unregisterFromEvent('));
      expect(screen, contains('eventController.deleteEvent('));
      expect(screen, contains('Event.normalizeStatus'));
      expect(screen, contains('void _showResponse('));
      expect(screen, contains('required String successTitle'));
      expect(screen, contains('if (response.success)'));
      expect(screen,
          contains("import 'package:adfoot/widgets/ad_system_notice.dart';"));
      expect(screen, contains('AdSystemNotice('));
      expect(screen, contains('_pendingEventActions'));
      expect(screen, contains('_isEventActionPending('));
      expect(screen, contains('_isOpenForRegistration(Event event)'));
      expect(screen, contains('_buildEventsOverview('));
      expect(screen, contains('_onlyMine'));
      expect(screen, contains('event.organisateur.nom.toLowerCase()'));
      expect(screen, contains('Icons.mark_email_unread_outlined'));
      expect(screen, contains('Créer un événement'));
      expect(screen, contains('return Wrap('));
      expect(
        screen,
        contains('_buildEmptyState(currentUser, filteredOut: true)'),
      );
      expect(screen, contains('_resetFilters()'));
      expect(screen, contains('_openEditEventForm(event)'));
      expect(screen, contains('final isFull = _isFull(event);'));
      expect(screen, contains('S’inscrire'));
      expect(screen, isNot(contains('AdFeedback.success(')));
      expect(screen, isNot(contains("const Text('Details')")));
    });

    test(
        'event controller and repository keep explicit failures and transactions',
        () {
      final controller =
          File('lib/controller/event_controller.dart').readAsStringSync();
      final repository =
          File('lib/services/events/event_repository.dart').readAsStringSync();

      expect(controller, contains('Future<ActionResponse> createEvent'));
      expect(controller, contains('Future<ActionResponse> updateEvent'));
      expect(controller, contains('Future<ActionResponse> deleteEvent'));
      expect(controller, contains('Future<ActionResponse> registerToEvent'));
      expect(
          controller, contains('Future<ActionResponse> unregisterFromEvent'));
      expect(controller, contains('_assertPublisherAuthorized'));
      expect(controller, contains('sendEventFanout'));

      expect(repository, contains('class EventRepositoryException'));
      expect(repository, contains('runTransaction'));
      expect(repository, contains('capacity_reached'));
      expect(repository, contains('already_registered'));
      expect(repository, contains('not_registered'));
      expect(repository, contains('event_closed'));
    });

    test('event details stay in-app and tolerate transient missing session',
        () {
      final details =
          File('lib/screens/event_detail_screen.dart').readAsStringSync();

      expect(details, contains('final AppUser? currentUser'));
      expect(details, contains('currentUser != null &&'));
      expect(details,
          contains('await Get.find<EventController>().fetchEvents();'));
      expect(details, contains('Get.back(result: updated);'));
      expect(details, contains('current.uid == other.uid'));
      expect(details, contains('Aucun participant pour le moment.'));
      expect(details, isNot(contains('Get.find<UserController>().user!')));
      expect(details, isNot(contains('Get.offAllNamed(AppRoutes.main')));
    });
  });
}
