import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/services/chat/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  test(
      'runtime harness covers first contact, chat opening state and message deletion',
      () async {
    final harness = await ChatTestHarness.create(
      enforceProjectRules: true,
    );
    addTearDown(harness.dispose);

    final result = await harness.chatController.startGuidedConversation(
      currentUser: harness.currentUser,
      otherUser: harness.otherUser,
      context: ContactContext.profile(
        profileUid: harness.otherUser.uid,
        title: harness.otherUser.nom,
      ),
      contactReason: ContactReasonCode.trial,
      introMessage: 'Nous voulons vous observer ce week-end.',
    );

    expect(result.conversationCreated, isTrue);
    expect(result.createdIntake, isTrue);
    expect(
      result.conversationId,
      ChatRepository.buildConversationId('user_a', 'user_b'),
    );

    final conversation = await harness.chatController
        .watchConversationById(result.conversationId)
        .firstWhere((item) => item != null);
    expect(conversation, isNotNull);
    expect(conversation!.contactReason, ContactReasonCode.trial);
    expect(conversation.contactIntakeId, result.contactIntake!.id);

    await harness.chatController.setActiveConversation(
      uid: harness.currentUser.uid,
      conversationId: result.conversationId,
    );

    final currentUserDoc =
        await harness.firestore
            .collection('users')
            .doc(harness.currentUser.uid)
            .get();
    expect(currentUserDoc.data()?['activeConversationId'], result.conversationId);

    final messages = await harness.chatController
        .getMessages(result.conversationId)
        .firstWhere((items) => items.isNotEmpty);
    expect(messages, hasLength(1));
    expect(messages.first.contenu, contains('Premier contact Adfoot.'));

    await harness.chatController.deleteMessage(
      result.conversationId,
      messages.first.id,
    );

    final conversationDoc =
        await harness.firestore
            .collection('conversations')
            .doc(result.conversationId)
            .get();
    final conversationData = conversationDoc.data() ?? <String, dynamic>{};
    final remainingMessages = await harness.firestore
        .collection('conversations')
        .doc(result.conversationId)
        .collection('messages')
        .get();

    expect(remainingMessages.docs, isEmpty);
    expect(conversationData.containsKey('lastMessage'), isFalse);
    expect(conversationData.containsKey('lastMessageDate'), isFalse);
    expect(harness.projectRulesEnforced, isTrue);
    expect(
      (conversationData['unreadCountByUser'] as Map<String, dynamic>?)?[
        harness.otherUser.uid
      ],
      0,
    );
  });

  test('runtime harness keeps a sent message when notification delivery fails',
      () async {
    final harness = await ChatTestHarness.create(
      notificationSender: ({
        required String title,
        required String body,
        required String recipientUid,
        required String contextType,
        required String contextData,
      }) async {
        throw StateError('push offline');
      },
    );
    addTearDown(harness.dispose);

    final result = await harness.chatController.startGuidedConversation(
      currentUser: harness.currentUser,
      otherUser: harness.otherUser,
      context: ContactContext.discovery(title: 'Annuaire'),
      contactReason: ContactReasonCode.information,
      introMessage: 'Premier contact guide.',
    );

    await harness.chatController.sendMessage(
      conversationId: result.conversationId,
      senderId: harness.currentUser.uid,
      recipientId: harness.otherUser.uid,
      content: 'Bonjour, disponible pour echanger ?',
      skipPermissionCheck: true,
    );

    final messages = await harness.firestore
        .collection('conversations')
        .doc(result.conversationId)
        .collection('messages')
        .orderBy('dateEnvoi', descending: true)
        .get();

    expect(messages.docs.length, 2);
    expect(
      messages.docs.first.data()['contenu'],
      'Bonjour, disponible pour echanger ?',
    );
  });
}
