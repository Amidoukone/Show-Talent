import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Auth-guarded collection bootstrap', () {
    test('event controller waits for auth before starting listeners', () {
      final content =
          File('lib/controller/event_controller.dart').readAsStringSync();

      expect(content, contains('AuthSessionService'));
      expect(content, contains('idTokenChanges().listen'));
      expect(content, contains('_stopEventsStream(clearData: true)'));
      expect(
        content,
        contains(
            'if (hasResolvedSession && _authSessionService.currentUser != null)'),
      );
    });

    test('offre controller waits for auth before starting listeners', () {
      final content =
          File('lib/controller/offre_controller.dart').readAsStringSync();

      expect(content, contains('AuthSessionService'));
      expect(content, contains('idTokenChanges().listen'));
      expect(content, contains('_stopOffresStream(clearData: true)'));
      expect(
        content,
        contains(
            'if (hasResolvedSession && _authSessionService.currentUser != null)'),
      );
    });
  });
}
