import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Settings and follow release guardrails', () {
    test('settings screen exposes an explicit invalid session state', () {
      final settings =
          File('lib/screens/setting_screen.dart').readAsStringSync();

      expect(settings, contains('bool _sessionUnavailable = false;'));
      expect(settings, contains('_authSessionService.currentUser?.uid'));
      expect(settings, contains("title: 'Session invalide'"));
      expect(
        settings,
        contains('Impossible de charger les parametres du compte.'),
      );
    });

    test(
        'follow list button resolves current uid defensively and clears loading',
        () {
      final follow =
          File('lib/screens/follow_list_screen.dart').readAsStringSync();

      expect(follow, contains('AuthSessionService'));
      expect(
        follow,
        contains("Get.find<UserController>().user?.uid ??"),
      );
      expect(follow, contains("_authSessionService.currentUser?.uid"));
      expect(follow, contains('try {'));
      expect(follow, contains('} finally {'));
      expect(follow, contains('_isLoading = false;'));
      expect(follow,
          isNot(contains("if (Get.find<UserController>().user == null) {")));
    });
  });
}
