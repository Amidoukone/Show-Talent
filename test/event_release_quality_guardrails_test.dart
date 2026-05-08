import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Event release quality guardrails', () {
    test('event form awaits controller result before success feedback', () {
      final form =
          File('lib/screens/event_form_screen.dart').readAsStringSync();

      expect(form, contains('Future<void> _handleSubmit() async'));
      expect(form, contains('await eventController.updateEvent'));
      expect(form, contains('await eventController.createEvent'));
      expect(form, contains('if (!response.success)'));
      expect(form, contains('AdFeedback.error('));
      expect(form, contains('AdFeedback.success('));
    });

    test('event list reacts to action responses for register/unregister/delete',
        () {
      final screen =
          File('lib/screens/event_list_screen.dart').readAsStringSync();

      expect(screen, contains('await eventController.registerToEvent'));
      expect(screen, contains('await eventController.unregisterFromEvent'));
      expect(screen, contains('await eventController.deleteEvent'));
      expect(screen, contains('Event.normalizeStatus'));
      expect(screen, contains('void _showResponse(ActionResponse response)'));
      expect(screen, contains('if (response.success)'));
      expect(screen, contains('return Wrap('));
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
      expect(details, contains('Get.back(result: true);'));
      expect(details, isNot(contains('Get.find<UserController>().user!')));
      expect(details, isNot(contains('Get.offAllNamed(AppRoutes.main')));
    });
  });
}
