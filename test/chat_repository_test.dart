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
}
