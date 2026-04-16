import 'package:adfoot/utils/auth_error_mapper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthErrorMapper', () {
    test('maps CONFIGURATION_NOT_FOUND to an actionable environment message',
        () {
      final error = FirebaseAuthException(
        code: 'internal-error',
        message: 'An internal error has occurred. [ CONFIGURATION_NOT_FOUND ]',
      );

      final message = AuthErrorMapper.toMessage(error);

      expect(message, contains('Firebase Authentication'));
      expect(message, contains('Email/Password'));
    });
  });
}
