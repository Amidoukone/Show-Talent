import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Settings and follow release guardrails', () {
    test('settings screen exposes an explicit invalid session state', () {
      final settings =
          File('lib/screens/setting_screen.dart').readAsStringSync();

      expect(settings, contains('bool _sessionUnavailable = false;'));
      expect(settings, contains('_authSessionService.currentUser?.uid'));
      expect(settings, contains('settings == null'));
      expect(settings, contains('_retryLoadUserSettings'));
      expect(settings, contains("title: 'Session invalide'"));
      expect(settings, contains("label: const Text('Réessayer')"));
      expect(
        settings,
        contains('Impossible de charger les paramètres du compte.'),
      );
    });

    test('settings refresh shared user state after privacy changes', () {
      final settings =
          File('lib/screens/setting_screen.dart').readAsStringSync();

      expect(settings,
          contains("import 'package:adfoot/controller/user_controller.dart';"));
      expect(settings, contains('Get.isRegistered<UserController>()'));
      expect(settings, contains('Get.find<UserController>().refreshUser()'));
      expect(settings, contains("case 'recruteur':"));
      expect(settings, contains("case 'agent':"));
      expect(
        settings,
        contains('Autoriser les talents et partenaires à vous contacter.'),
      );
    });

    test('tools screen uses production-ready account sections', () {
      final settings =
          File('lib/screens/setting_screen.dart').readAsStringSync();

      expect(settings,
          contains("import 'package:adfoot/widgets/ad_app_bar.dart';"));
      expect(settings, contains('appBar: const AdAppBar('));
      expect(settings, contains("title: 'Outils'"));
      expect(settings, contains("subtitle: 'Compte et sécurité'"));
      expect(settings, contains('AdSurfaceCard'));
      expect(settings, contains('_buildToolsHeader'));
      expect(settings, contains('_buildSectionCard'));
      expect(settings, contains('_buildSwitchTile'));
      expect(settings, contains('_savingPrivacySettings'));
      expect(settings, contains('_handleSignOut'));
      expect(
        settings,
        contains('Get.to(() => ProfileScreen(uid: uid, isReadOnly: false))'),
      );
      expect(settings, contains('_showDataUsageNotice'));
      expect(settings, contains('_showSupportNotice'));
      expect(settings, contains('AdButtonKind.danger'));
      expect(settings, contains('Supprimer mon compte'));
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
      final repository =
          File('lib/services/users/follow_repository.dart').readAsStringSync();
      final backend =
          File('functions/src/follow_actions.ts').readAsStringSync();
      final exports = File('functions/src/index.ts').readAsStringSync();

      expect(controller, contains('_followRepository.followUser'));
      expect(controller, contains('_followRepository.unfollowUser'));
      expect(repository, contains("httpsCallable("));
      expect(
        repository,
        contains("CallableAuthGuard.callDataWithHttpFallback"),
      );
      expect(repository, contains("'followUser'"));
      expect(repository, contains("'unfollowUser'"));
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
