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
    // La localisation est affichee une fois, dans la section du profil, et
    // plus dans l'en-tete. Elle y vivait en pastille, sur la meme carte que
    // le nom et le club deja portes ailleurs -- et c'est ce libelle-la, le
    // plus long des trois, qui debordait du cadre par la droite.
    //
    // Assertions inversees plutot que supprimees : le doublon est revenu une
    // fois, il peut revenir deux.
    expect(profileHeader, isNot(contains('user.city')));
    expect(profileHeader, isNot(contains('user.region')));
    expect(profileHeader, isNot(contains('user.country')));

    // Le nom et le role appartiennent a la barre du haut, pas a la carte.
    expect(profileHeader, isNot(contains('user.nom')));
    expect(profileHeader, isNot(contains('_profileRoleLabel(user)')));
    expect(profile, contains('title: user.nom.isNotEmpty ? user.nom'));
    expect(profile, contains('subtitle: _profileRoleLabel(user)'));

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
    // Le poste libre a quitte l'editeur de base pour le joueur : il se coche
    // dans le profil avance, contre la liste fermee que la recherche filtre.
    // Le coach le garde -- sa fonction n'a pas d'equivalent dans cette liste.
    expect(editProfile, contains('Vos postes se cochent dans le profil avancé'));
    expect(editProfile, contains('if (_isCoach) ...['));
    expect(editProfile, contains("patch['currentClubName']"));
    expect(editProfile, isNot(contains("patch['team']")));
    expect(editProfile, isNot(contains("patch['clubActuel']")));
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
