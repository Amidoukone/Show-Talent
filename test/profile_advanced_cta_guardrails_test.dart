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
    // The literal wording moved into the GetX catalog (badge styling
    // switches on the stable ProfileTrustStatus.verified enum value, not on
    // the translated label text -- see [[project_adfoot_i18n_ios_effort]]).
    final videoTranslations = File(
      'lib/l10n/video_ui_translations.dart',
    ).readAsStringSync();

    expect(
      profile,
      contains('final hasAdvancedProfile = user.hasAdvancedProfile;'),
    );
    expect(profile, contains('l10n.profileCtaUpdatePlayerMessage'));
    expect(profile, contains('l10n.profileCtaUpdateButton'));
    expect(profile, contains('l10n.profileCtaCompleteButton'));
    expect(profile, contains('constraints.maxWidth < 380'));
    expect(profileSurface, contains('maxLines: 2'));
    expect(profileSurface, contains('overflow: TextOverflow.ellipsis'));
    expect(profileSurface, contains('user.isProfileTrusted'));
    expect(profileSurface, contains('_ProfileBadgeKind.verifiedTrust'));
    expect(
      videoTranslations,
      contains("'profileTrustVerified': 'Vérifié par Adfoot'"),
    );
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
    // The literal wording moved into the ARB template (l10n.editAdvancedProfile*).
    final arbFr = File('lib/l10n/app_fr.arb').readAsStringSync();
    expect(
      advancedEditor,
      contains('l10n.editAdvancedProfilePlayerSaveFailedMessage'),
    );
    expect(arbFr, contains('Le profil joueur n’a pas été enregistré'));
    expect(
      advancedEditor,
      contains('l10n.editAdvancedProfileScoutSaveFailedMessage'),
    );
    expect(arbFr, contains('Le dossier scout n’a pas été enregistré'));
    expect(controller, contains('bool _isAccessDenied(Object error)'));
    expect(
      controller,
      contains('throw const ProfileAccessRevokedException();'),
    );
    expect(
      controller,
      isNot(contains('if (ProfileRepository.isUnauthorized(e))')),
    );
    // The literal wording moved into the ARB template (l10n.editProfileSaveDenied*).
    expect(
      arbFr,
      contains('"editProfileSaveDeniedTitle": "Sauvegarde refusée"'),
    );
    expect(playerAdvanced, contains('} catch (_) {'));
    expect(playerAdvanced, contains('l10n.editProfileSaveDeniedTitle'));
    expect(playerStats, contains('} catch (_) {'));
    expect(playerAdvanced, contains('Map<String, dynamic> buildPatch()'));
    expect(playerStats, contains('Map<String, dynamic> buildPatch()'));
    expect(playerStats, contains('l10n.editProfileSaveDeniedTitle'));
    // Le poste est ecrit en codes, jamais en libelles : c'est ce qui rend la
    // fiche filtrable. Le libelle libre a disparu avec la refonte, et le
    // laisser revenir ici rouvrirait la porte au CSV.
    expect(playerAdvanced, contains("_currentProfile().toPatch()"));
    expect(playerAdvanced, isNot(contains('_csvToList')));
    expect(playerAdvanced, isNot(contains("'skills'")));
    expect(playerStats, contains("'openToOpportunities': _openToTrials"));
  });
}
