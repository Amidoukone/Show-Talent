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

    test('follow controller delegates mutations to callable backend', () {
      final controller =
          File('lib/controller/follow_controller.dart').readAsStringSync();
      final backend =
          File('functions/src/follow_actions.ts').readAsStringSync();
      final exports = File('functions/src/index.ts').readAsStringSync();

      expect(controller, contains("httpsCallable("));
      expect(
        controller,
        contains("CallableAuthGuard.callDataWithHttpFallback"),
      );
      expect(controller, contains("'followUser'"));
      expect(controller, contains("'unfollowUser'"));
      expect(backend, contains('export const followUser = onCall('));
      expect(backend, contains('export const unfollowUser = onCall('));
      expect(exports, contains('export {followUser, unfollowUser}'));
    });

    test('follow list keeps coherent local UX details', () {
      final follow =
          File('lib/screens/follow_list_screen.dart').readAsStringSync();

      expect(follow, contains("assets/default_avatar.jpg"));
      expect(follow, contains('RefreshIndicator('));
      expect(
        follow,
        contains("widget.listType == 'followings' &&"),
      );
      expect(follow, contains('currentUserId == widget.listOwnerUid'));
      expect(follow, contains('widget.onRemove();'));
    });
  });
}
