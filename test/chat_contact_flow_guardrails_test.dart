import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chat contact flow guardrails', () {
    test('profile and event entry points use the guided first contact flow',
        () {
      final profileScreen =
          File('lib/screens/profile_screen.dart').readAsStringSync();
      final eventScreen =
          File('lib/screens/event_detail_screen.dart').readAsStringSync();

      expect(profileScreen, contains('ContactIntakeSheet'));
      expect(profileScreen, contains('startGuidedConversation'));
      expect(profileScreen, contains('findExistingConversationId'));

      expect(eventScreen, contains('ContactIntakeSheet'));
      expect(eventScreen, contains('startGuidedConversation'));
      expect(eventScreen, contains('ContactContext.event('));
    });

    test('chat screen surfaces guided contact metadata when present', () {
      final chatScreen =
          File('lib/screens/chat_screen.dart').readAsStringSync();
      final conversationModel =
          File('lib/models/message_converstion.dart').readAsStringSync();
      final controller =
          File('lib/controller/chat_controller.dart').readAsStringSync();
      final repository =
          File('lib/services/chat/chat_repository.dart').readAsStringSync();

      expect(chatScreen, contains('watchConversationById'));
      expect(chatScreen, contains('Premier contact cadré'));
      expect(chatScreen, contains('Suivi agence :'));
      expect(chatScreen, contains('Donner un retour sur la mise en relation'));
      expect(chatScreen, contains('_showContactFeedbackSheet'));
      expect(chatScreen, contains('ContactIntakeFeedbackService'));
      expect(conversationModel, contains('contactReason'));
      expect(conversationModel, contains('contextTitle'));
      expect(conversationModel, contains('latestParticipantFeedbackStatus'));
      expect(controller, contains('Notification message non bloquante: '));
      expect(controller, contains('Erreur verification messagerie firebase :'));
      expect(repository, contains('_recoverMissingGuidedContactIntake'));
      expect(repository, contains('_createAndLinkGuidedContactIntake'));
    });

    test(
        'shared backend exposes an admin follow-up callable for contact intakes',
        () {
      final callableFile = File(
        'functions/src/admin_contact_intake_actions.ts',
      ).readAsStringSync();
      final indexFile = File('functions/src/index.ts').readAsStringSync();
      final feedbackService = File(
        'lib/services/contact_intake_feedback_service.dart',
      ).readAsStringSync();

      expect(callableFile, contains('adminSetContactIntakeFollowUp'));
      expect(callableFile, contains('submitContactIntakeFeedback'));
      expect(callableFile, contains('latestParticipantFeedbackStatus'));
      expect(callableFile, contains('agencyFollowUpStatus'));
      expect(callableFile,
          contains('recoverMissingContactIntakeFromConversation'));
      expect(callableFile, contains('conversationId'));
      expect(indexFile, contains('adminSetContactIntakeFollowUp'));
      expect(indexFile, contains('submitContactIntakeFeedback'));
      expect(feedbackService,
          contains("httpsCallable('submitContactIntakeFeedback')"));
      expect(feedbackService, contains('normalizedCode'));
    });
  });
}
