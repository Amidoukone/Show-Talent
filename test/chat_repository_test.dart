import 'dart:io';

import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/services/chat/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conversation id is deterministic and order-independent', () {
    final first = ChatRepository.buildConversationId('user_b', 'user_a');
    final second = ChatRepository.buildConversationId('user_a', 'user_b');

    expect(first, equals('user_a__user_b'));
    expect(second, equals('user_a__user_b'));
    expect(first, equals(second));
  });

  test('guided first contact message keeps context and reason explicit', () {
    final message = ChatRepository.buildGuidedFirstMessage(
      context: ContactContext.event(
        eventId: 'event-1',
        title: 'Tournoi Detection',
      ),
      reasonCode: ContactReasonCode.trial,
      introMessage: 'Nous souhaitons vous observer samedi.',
    );

    expect(message, contains('Premier contact Adfoot.'));
    expect(message, contains('Essai / Evaluation'));
    expect(message, contains('Tournoi Detection'));
    expect(message, contains('observer samedi'));
  });

  test('chat repository avoids direct reads on missing conversation docs', () {
    final repository =
        File('lib/services/chat/chat_repository.dart').readAsStringSync();

    expect(repository, contains(".where('utilisateurIds', arrayContains:"));
    expect(repository, contains('final existingConversationId = await findExistingConversationId('));
    expect(repository, contains('await conversationRef.set(newConversation.toMap());'));
    expect(repository, isNot(contains('.limit(100)')));
    expect(
      repository,
      isNot(contains(
        "final doc = await _conversationsCollection.doc(conversationId).get();",
      )),
    );
    expect(
      repository,
      isNot(contains('final snap = await txn.get(conversationRef);')),
    );
  });

  test('chat repository keeps delete-message summary and unread state coherent',
      () {
    final repository =
        File('lib/services/chat/chat_repository.dart').readAsStringSync();

    expect(repository, contains('await messageRef.delete();'));
    expect(repository, contains("patch['lastMessage'] = FieldValue.delete();"));
    expect(
      repository,
      contains(
        "patch['lastMessageDate'] = FieldValue.delete();",
      ),
    );
    expect(
      repository,
      contains("patch['unreadCountByUser.\${deletedMessage.destinataireId}']"),
    );
  });
}
