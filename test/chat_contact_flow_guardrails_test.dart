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

      expect(chatScreen, contains('watchConversationById'));
      expect(chatScreen, contains('Premier contact cadre'));
      expect(chatScreen, contains('Suivi agence:'));
      expect(conversationModel, contains('contactReason'));
      expect(conversationModel, contains('contextTitle'));
    });

    test(
        'shared backend exposes an admin follow-up callable for contact intakes',
        () {
      final callableFile = File(
        'functions/src/admin_contact_intake_actions.ts',
      ).readAsStringSync();
      final indexFile = File('functions/src/index.ts').readAsStringSync();

      expect(callableFile, contains('adminSetContactIntakeFollowUp'));
      expect(callableFile, contains('agencyFollowUpStatus'));
      expect(indexFile, contains('adminSetContactIntakeFollowUp'));
    });
  });
}
