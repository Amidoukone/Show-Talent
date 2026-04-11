import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chat session resolution guardrails', () {
    test(
        'select user screen resolves the current session from the shared source',
        () {
      final content =
          File('lib/screens/select_user_screen.dart').readAsStringSync();

      expect(content, contains('AuthSessionService'));
      expect(content, contains('userController.user ?? authController.user'));
      expect(content, contains('canAppearInMessagingDirectory'));
      expect(content, contains('CircularProgressIndicator'));
    });

    test('conversation and chat screens no longer rely only on AuthController',
        () {
      final conversation =
          File('lib/screens/conversation_screen.dart').readAsStringSync();
      final chat = File('lib/screens/chat_screen.dart').readAsStringSync();

      expect(
          conversation, contains('userController.user ?? authController.user'));
      expect(conversation, contains('AuthSessionService'));
      expect(chat,
          contains('_userController.user ?? AuthController.instance.user'));
      expect(chat, contains('_authSessionService.currentUser != null'));
    });
  });
}
