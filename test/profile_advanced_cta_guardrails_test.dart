import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile advanced CTA stays contextual and mobile-safe', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final profileWidgets = File(
      'lib/screens/profile_screen_widgets.dart',
    ).readAsStringSync();
    final profileCards = File(
      'lib/widgets/ad_profile_cards.dart',
    ).readAsStringSync();
    final profileSurface = '$profile\n$profileWidgets\n$profileCards';

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
    // Une miniature cassée montre le repli, jamais une image brisée.
    // Le mécanisme a changé — `CachedNetworkImage` remplace `Image.network`,
    // qui n'avait aucun cache disque et ignorait le préchargement du
    // contrôleur — mais l'invariant est le même.
    expect(profileSurface, contains('errorWidget: (_, _, _) => fallback()'));
    expect(profileSurface, contains('placeholder: (_, _) => fallback()'));
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
    expect(advancedEditor, contains('_mergePatchMaps'));
    expect(advancedEditor, contains('profileState.buildPatch()'));
    expect(advancedEditor, contains('scoutState.buildPatch()'));
    expect(
      advancedEditor,
      isNot(contains('_playerProfileKey.currentState?.save')),
    );
    expect(advancedEditor, contains('Le profil joueur n’a pas été enregistré'));
    expect(advancedEditor, contains('Le dossier scout n’a pas été enregistré'));
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
    expect(playerAdvanced, contains('Sauvegarde refusée'));
    expect(playerStats, contains('} catch (_) {'));
    expect(playerAdvanced, contains('Map<String, dynamic> buildPatch()'));
    expect(playerStats, contains('Map<String, dynamic> buildPatch()'));
    expect(playerStats, contains('Sauvegarde refusée'));
    expect(playerAdvanced, contains("if (positions.isNotEmpty) 'position'"));
    expect(playerStats, contains("'openToOpportunities': _openToTrials"));
  });
}
