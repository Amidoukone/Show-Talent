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
}
