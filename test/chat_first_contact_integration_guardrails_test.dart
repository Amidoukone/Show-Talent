import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chat first-contact integration guardrails', () {
    test(
        'first contact entry points keep the existing-conversation fallback before guided creation',
        () {
      final profileScreen =
          File('lib/screens/profile_screen.dart').readAsStringSync();
      final eventScreen =
          File('lib/screens/event_detail_screen.dart').readAsStringSync();
      final selectUserScreen =
          File('lib/screens/select_user_screen.dart').readAsStringSync();

      expect(profileScreen, contains('findExistingConversationId('));
      expect(profileScreen, contains('startGuidedConversation('));
      expect(profileScreen, contains('ContactIntakeSheet('));
      expect(profileScreen, contains('ChatScreen('));

      expect(eventScreen, contains('findExistingConversationId('));
      expect(eventScreen, contains('startGuidedConversation('));
      expect(eventScreen, contains('ContactIntakeSheet('));
      expect(eventScreen, contains('ChatScreen('));

      expect(selectUserScreen, contains('findExistingConversationId('));
      expect(selectUserScreen, contains('startGuidedConversation('));
      expect(selectUserScreen, contains('ContactIntakeSheet('));
      expect(selectUserScreen, contains('ChatScreen('));
    });

    test(
        'repository keeps the guided first-contact pipeline wired through conversation, message and intake persistence',
        () {
      final repository =
          File('lib/services/chat/chat_repository.dart').readAsStringSync();

      expect(repository, contains('buildConversationId('));
      expect(
        repository,
        contains(
            'final existingConversationId = await findExistingConversationId('),
      );
      expect(
        repository,
        contains('await conversationRef.set(newConversation.toMap());'),
      );
      expect(repository, contains('persistMessageAndConversation('));
      expect(repository, contains('_createAndLinkGuidedContactIntake('));
      expect(repository, contains('_recoverMissingGuidedContactIntake('));
      expect(repository, contains('buildGuidedFirstMessage('));
      expect(repository, contains("createdVia: 'guided_first_contact'"));
      expect(repository, contains("'contactIntakeId': intake.id"));
    });

    test(
        'chat opening and deletion path stays coherent across chat screen, controller and conversation list',
        () {
      final chatScreen =
          File('lib/screens/chat_screen.dart').readAsStringSync();
      final controller =
          File('lib/controller/chat_controller.dart').readAsStringSync();
      final repository =
          File('lib/services/chat/chat_repository.dart').readAsStringSync();
      final conversationScreen =
          File('lib/screens/conversation_screen.dart').readAsStringSync();

      expect(chatScreen, contains('watchConversationById('));
      expect(chatScreen, contains('getMessages(widget.conversationId)'));
      expect(chatScreen, contains('setActiveConversation('));
      expect(chatScreen, contains('touchActiveConversation(uid)'));
      expect(chatScreen, contains('deleteMessage(widget.conversationId,'));
      expect(chatScreen, contains('markMessagesAsRead(widget.conversationId,'));

      expect(controller, contains('await _chatRepository.deleteMessage('));
      expect(controller, contains('_syncUnreadFromConversation('));
      expect(controller, contains('Notification message non bloquante: '));
      expect(controller, contains('Erreur vérification messagerie firebase :'));

      expect(repository, contains('await messageRef.delete();'));
      expect(
          repository, contains("patch['lastMessage'] = FieldValue.delete();"));
      expect(
        repository,
        contains(
            "patch['unreadCountByUser.\${deletedMessage.destinataireId}']"),
      );

      expect(
          conversationScreen, contains('deleteConversation(conversationId)'));
      expect(conversationScreen, contains('ValueKey("conv_\${user.uid}")'));
    });

    test('first contact and feedback sheets stay keyboard-safe', () {
      final contactIntakeSheet =
          File('lib/widgets/contact_intake_sheet.dart').readAsStringSync();
      final chatScreen =
          File('lib/screens/chat_screen.dart').readAsStringSync();
      final adButton = File('lib/widgets/ad_button.dart').readAsStringSync();

      expect(contactIntakeSheet, contains('ConstrainedBox('));
      expect(contactIntakeSheet, contains('SingleChildScrollView('));
      expect(
        contactIntakeSheet,
        contains(
          'keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag',
        ),
      );
      expect(
        contactIntakeSheet,
        contains('scrollPadding: const EdgeInsets.only(bottom: 120)'),
      );

      expect(chatScreen, contains('class MessageInputBar'));
      expect(
        chatScreen,
        contains('minimum: const EdgeInsets.only(bottom: 8)'),
      );
      expect(
        chatScreen,
        contains(
          'keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag',
        ),
      );
      expect(chatScreen, isNot(contains('bottom > 0 ? bottom + 8')));

      expect(adButton, contains('if (icon == null)'));
      expect(adButton, isNot(contains('icon ?? const SizedBox.shrink()')));
    });
  });
}
