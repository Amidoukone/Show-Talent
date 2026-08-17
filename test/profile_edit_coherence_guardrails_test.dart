import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('base profile editor covers fields visible on the profile surface', () {
    final editProfile = File(
      'lib/screens/edit_profil_screen.dart',
    ).readAsStringSync();
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final profileHeader = File(
      'lib/screens/profile_screen_widgets.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/controller/profile_controller.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/services/users/profile_repository.dart',
    ).readAsStringSync();

    expect(profile, contains('user.city'));
    expect(profile, contains('user.region'));
    expect(profile, contains('user.country'));
    expect(profile, contains('_bioSectionTitle(user)'));
    expect(profile, contains('Présentation du joueur'));
    expect(profile, contains('_emptyBioMessage(user)'));
    expect(profileHeader, contains('user.city'));
    expect(profileHeader, contains('user.region'));
    expect(profileHeader, contains('user.country'));

    expect(editProfile, contains('_cityController'));
    expect(editProfile, contains('_regionController'));
    expect(editProfile, contains('_countryController'));
    expect(editProfile, contains("_putNullableStringPatch(patch, 'city'"));
    expect(
      editProfile,
      contains("_putNullableStringPatch(\n        patch,\n        'region'"),
    );
    expect(
      editProfile,
      contains("_putNullableStringPatch(\n        patch,\n        'country'"),
    );
    expect(editProfile, contains('Localisation'));
    expect(
      editProfile.indexOf('Identité sportive du joueur'),
      lessThan(editProfile.indexOf('Localisation')),
    );
    expect(editProfile, contains('Renseignez le poste principal et le club'));
    expect(editProfile, contains('_bioController'));
    expect(editProfile, isNot(contains('if (!user.isFan) ...[')));

    expect(controller, contains("applyNullableString('city'"));
    expect(controller, contains("applyNullableString('region'"));
    expect(controller, contains("applyNullableString('country'"));
    expect(repository, contains("'city'"));
    expect(repository, contains("'region'"));
    expect(repository, contains("'country'"));
    expect(repository, contains('authRefreshTimeout'));
    expect(repository, isNot(contains('currentUser.getIdToken(true).timeout')));
    expect(repository, contains('_isTransientAuthTokenRefreshError'));
    expect(repository, contains('currentUser.getIdToken().timeout'));
    expect(repository, contains("import '../app_check_service.dart';"));
    expect(repository, contains('appCheckWriteTimeout'));
    // App Check must stay a background warm-up here, never a gate: Firestore
    // and Storage are UNENFORCED for this project, so blocking a profile
    // write on a Play Integrity token only invents failures. Guard against
    // the old awaited/throwing shape coming back.
    expect(repository, contains('_warmUpAppCheckForWrite'));
    expect(repository, isNot(contains('_ensureAppCheckReadyForWrite')));
    expect(
      repository,
      isNot(contains("plugin: 'firebase_app_check'")),
    );
    expect(repository, isNot(contains('await _appCheckReady(')));
  });
}
