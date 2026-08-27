import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Settings and follow release guardrails', () {
    test('settings screen exposes an explicit invalid session state', () {
      final settings = File(
        'lib/screens/setting_screen.dart',
      ).readAsStringSync();

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
      final settings = File(
        'lib/screens/setting_screen.dart',
      ).readAsStringSync();

      expect(
        settings,
        contains("import 'package:adfoot/controller/user_controller.dart';"),
      );
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
      final settings = File(
        'lib/screens/setting_screen.dart',
      ).readAsStringSync();

      expect(
        settings,
        contains("import 'package:adfoot/widgets/ad_app_bar.dart';"),
      );
      expect(settings, contains('appBar: const AdAppBar('));
      expect(settings, contains("title: 'Outils'"));
      expect(settings, contains("subtitle: 'Compte et sécurité'"));
      expect(settings, contains('AdSurfaceCard'));
      expect(settings, contains('_buildToolsHeader'));
      expect(settings, contains('_buildSectionCard'));
      expect(settings, contains('_buildSwitchTile'));
      expect(settings, contains('_savingPrivacySettings'));
      expect(settings, contains('_handleSignOut'));
      expect(settings, contains('_showDataUsageNotice'));
      expect(settings, contains('_showSupportNotice'));
      expect(settings, contains('AdButtonKind.danger'));
      expect(settings, contains('Supprimer mon compte'));
    });

    test('tools screen holds no profile identity and no profile route', () {
      final settings = File(
        'lib/screens/setting_screen.dart',
      ).readAsStringSync();

      // Outils used to open a second, fully editable copy of the profile and
      // to print the account's name and e-mail in its own header. Two routes
      // to the same editors is how "Compléter le profil" ended up reachable
      // from a settings screen. The Profil destination owns all of it now.
      expect(
        settings,
        isNot(contains('ProfileScreen')),
        reason: 'Outils must not route to the profile',
      );
      expect(settings, isNot(contains('_openProfile')));
      expect(settings, isNot(contains("title: 'Voir le profil'")));
      expect(settings, isNot(contains("label: 'Voir profil'")));
      expect(
        settings,
        isNot(contains('user?.email')),
        reason: 'no account identity in a settings header',
      );
      expect(settings, isNot(contains('_buildStatusPill')));
      expect(settings, isNot(contains('_roleDisplayLabel')));
      expect(
        settings,
        isNot(contains("import 'package:adfoot/models/user.dart';")),
      );

      // What it keeps: the session and the account controls.
      expect(settings, contains("title: 'Se déconnecter'"));
      expect(settings, contains("title: 'Confidentialité'"));
      expect(settings, contains('Supprimer mon compte'));
      expect(settings, contains('Vos informations sont dans Profil'));
    });

    test('the profile surface owns the account identity', () {
      final profile = File(
        'lib/screens/profile_screen.dart',
      ).readAsStringSync();
      final header = File(
        'lib/screens/profile_screen_widgets.dart',
      ).readAsStringSync();

      // The e-mail line moved out of the Outils header and has to land
      // somewhere — on the owner's profile, and only there.
      expect(header, contains('user.email.trim()'));
      expect(
        RegExp(
          r'if \(isOwnProfile &&\s*!isReadOnly &&\s*user\.email',
        ).hasMatch(header),
        isTrue,
        reason: 'an e-mail address is never shown to a visitor',
      );

      // Everything editable about the profile stays one tap from this screen.
      expect(profile, contains('EditProfileScreen('));
      expect(profile, contains('EditAdvancedProfileScreen('));
      expect(profile, contains('_buildAdvancedCtaIfNeededClean('));
      expect(profile, contains("tooltip: 'Outils',"));
    });

    test(
      'follow list button resolves current uid defensively and clears loading',
      () {
        final follow = File(
          'lib/screens/follow_list_screen.dart',
        ).readAsStringSync();

        expect(follow, contains('AuthSessionService'));
        expect(follow, contains("Get.find<UserController>().user?.uid ??"));
        expect(follow, contains("_authSessionService.currentUser?.uid"));
        expect(follow, contains('try {'));
        expect(follow, contains('} finally {'));
        expect(follow, contains('_isLoading = false;'));
        expect(
          follow,
          isNot(contains("if (Get.find<UserController>().user == null) {")),
        );
      },
    );

    test('follow controller delegates mutations to callable backend', () {
      final controller = File(
        'lib/controller/follow_controller.dart',
      ).readAsStringSync();
      final repository = File(
        'lib/services/users/follow_repository.dart',
      ).readAsStringSync();
      final backend = File(
        'functions/src/follow_actions.ts',
      ).readAsStringSync();
      final exports = File('functions/src/index.ts').readAsStringSync();

      expect(controller, contains('_followRepository.followUser'));
      expect(controller, contains('_followRepository.unfollowUser'));
      expect(repository, contains("httpsCallable("));
      expect(
        repository,
        contains("CallableAuthGuard.callDataWithHttpFallback"),
      );
      expect(repository, contains('_runFollowMutationWithRetry'));
      expect(repository, contains('Duration(seconds: 20)'));
      expect(repository, contains('_isTransientMutationError'));
      expect(repository, contains("'followUser'"));
      expect(repository, contains("'unfollowUser'"));
      expect(backend, contains('export const followUser = onCall('));
      expect(backend, contains('export const unfollowUser = onCall('));
      expect(exports, contains('export {followUser, unfollowUser}'));
    });

    test('follow controller rolls back optimistic state on backend rejection', () {
      final controller = File(
        'lib/controller/follow_controller.dart',
      ).readAsStringSync();

      expect(
        RegExp(
          r'else\s*\{\s*_syncLocalFollowingState\([\s\S]*?shouldFollow:\s*false',
        ).hasMatch(controller),
        isTrue,
      );
      expect(
        RegExp(
          r'else\s*\{\s*_syncLocalFollowingState\([\s\S]*?shouldFollow:\s*true',
        ).hasMatch(controller),
        isTrue,
      );
    });

    test('follow list keeps coherent local UX details', () {
      final follow = File(
        'lib/screens/follow_list_screen.dart',
      ).readAsStringSync();

      expect(follow, contains("assets/default_avatar.jpg"));
      expect(follow, contains('RefreshIndicator('));
      expect(follow, contains("widget.listType == 'followings' &&"));
      expect(follow, contains('currentUserId == widget.listOwnerUid'));
      expect(follow, contains('widget.onRemove();'));
    });
  });
}
