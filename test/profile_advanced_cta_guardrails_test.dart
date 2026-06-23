import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile advanced CTA stays contextual and mobile-safe', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final profileWidgets = File(
      'lib/screens/profile_screen_widgets.dart',
    ).readAsStringSync();
    final profileSurface = '$profile\n$profileWidgets';

    expect(
      profile,
      contains('final hasAdvancedProfile = user.hasAdvancedProfile;'),
    );
    expect(profile, contains('Gardez votre dossier scout'));
    expect(profile, contains("hasAdvancedProfile ? 'Mettre"));
    expect(profile, contains('constraints.maxWidth < 380'));
    expect(profileSurface, contains('maxLines: 2'));
    expect(profileSurface, contains('overflow: TextOverflow.ellipsis'));
    expect(profileSurface, contains('user.isProfileTrusted'));
    expect(profileSurface, contains('Vérifié par Adfoot'));
    expect(profileSurface, contains('errorBuilder: (_, _, _) => fallback()'));
    expect(
      profileSurface,
      contains('loadingBuilder: (context, child, loadingProgress)'),
    );
  });

  test('profile editors keep MVP and advanced save flows complete', () {
    final editProfile = File(
      'lib/screens/edit_profil_screen.dart',
    ).readAsStringSync();
    final advancedEditor = File(
      'lib/screens/edit_advanced_profile_screen.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/controller/profile_controller.dart',
    ).readAsStringSync();
    final playerAdvanced = File(
      'lib/widgets/advanced/player_advanced_form.dart',
    ).readAsStringSync();
    final playerStats = File(
      'lib/widgets/advanced/player_stats_availability_form.dart',
    ).readAsStringSync();

    expect(editProfile, contains('_positionController'));
    expect(editProfile, contains("patch['position']"));
    expect(editProfile, contains("label: user.role == 'coach'"));
    expect(advancedEditor, contains('IndexedStack'));
    expect(advancedEditor, isNot(contains('TabBarView(')));
    expect(controller, contains('bool _isAccessDenied(Object error)'));
    expect(
      controller,
      contains('throw const ProfileAccessRevokedException();'),
    );
    expect(
      controller,
      isNot(contains('if (ProfileRepository.isUnauthorized(e))')),
    );
    expect(playerAdvanced, contains('} catch (_) {'));
    expect(playerStats, contains('} catch (_) {'));
    expect(playerAdvanced, contains("if (positions.isNotEmpty) 'position'"));
    expect(playerStats, contains("'openToOpportunities': _openToTrials"));
  });
}
