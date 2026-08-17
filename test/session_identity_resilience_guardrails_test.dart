import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regressions from a real production report: after a while on a live device
/// the Edit button vanished from the user's own profile, and after clearing
/// app data the app came back signed in but completely empty, with the
/// profile stuck on "Profil indisponible / Chargement du profil impossible".
///
/// Three independent defects produced that, each of which turned a temporary
/// unknown into a permanent verdict.
void main() {
  group('identity survives a failed profile read', () {
    test('currentUid comes from Firebase Auth, not the profile document', () {
      final controller =
          File('lib/controller/auth_controller.dart').readAsStringSync();

      // Every caller asks an identity question ("is this my own profile?").
      // Sourcing it from the loaded AppUser meant a transient Firestore
      // failure made the user stop being themselves: isOwnProfile went false,
      // the Edit button disappeared and canViewProfile fell through to the
      // unavailable screen on their own account.
      expect(
        controller,
        contains('String? get currentUid => _authSessionService.currentUid'),
      );
      expect(
        controller,
        isNot(contains('String? get currentUid => _appUser.value?.uid')),
      );
    });

    test('an inconclusive session never downgrades a loaded profile', () {
      final controller =
          File('lib/controller/auth_controller.dart').readAsStringSync();
      final session =
          File('lib/services/auth/auth_session_service.dart').readAsStringSync();

      // AuthSessionService answers a transient failure with destination
      // `main` and no appUser — "the session stands, the profile is unknown".
      // Assigning that null through turned unknown into gone.
      expect(session, contains('_preserveCurrentSessionAfterTransientFailure'));
      expect(controller, contains('_applySessionSnapshot'));
      expect(controller, contains('_rehydrateAppUser'));

      // The old unconditional wipe must not come back.
      expect(
        controller,
        isNot(
          contains(
            '_appUser.value = snapshot.destination == '
            'AuthSessionDestination.main',
          ),
        ),
      );
    });

    test('a pending rehydrate cannot outlive sign-out', () {
      final controller =
          File('lib/controller/auth_controller.dart').readAsStringSync();

      // A slow read must not land a profile back into a signed-out session.
      expect(controller, contains('_rehydrateSerial'));
    });
  });

  group('a fresh session is not mistaken for a broken one', () {
    test('unauthenticated is treated as token propagation, not refusal', () {
      final profileRepo =
          File('lib/services/users/profile_repository.dart').readAsStringSync();
      final userRepo =
          File('lib/services/users/user_repository.dart').readAsStringSync();

      // Firestore reports 'unauthenticated' for a second or two after sign-in,
      // and reliably right after clearing app data. It matched no bucket, so
      // it produced the generic "Chargement du profil impossible" dead end.
      expect(profileRepo, contains("case 'unauthenticated'"));
      expect(profileRepo, contains('isTransientAuthPropagation'));
      expect(userRepo, contains("case 'unauthenticated'"));
    });

    test('the retry actually outlasts the token race', () {
      final profileRepo =
          File('lib/services/users/profile_repository.dart').readAsStringSync();

      // 300ms and 600ms both land before the token does, so all three
      // attempts failed on the same missing credential.
      expect(profileRepo, contains('900 * attempt'));
    });
  });

  group('supplementary reads cannot sink the profile', () {
    test('a private-contact failure degrades instead of throwing', () {
      final profileRepo =
          File('lib/services/users/profile_repository.dart').readAsStringSync();

      // Only fetchUser(includePrivateFields: true) — your own profile —
      // reaches this read, so an uncaught failure here hit exactly the owner
      // and collapsed the whole screen over a phone number.
      final method = profileRepo.substring(
        profileRepo.indexOf('Future<Map<String, dynamic>?> _fetchPrivateContact'),
      );
      final body = method.substring(0, method.indexOf('\n  }') + 4);

      expect(body, contains('try {'));
      expect(body, contains('return null;'));
    });

    test('both repositories degrade the same way', () {
      final profileRepo =
          File('lib/services/users/profile_repository.dart').readAsStringSync();
      final userRepo =
          File('lib/services/users/user_repository.dart').readAsStringSync();

      for (final source in <String>[profileRepo, userRepo]) {
        final index = source.indexOf('_fetchPrivateContact(String uid)');
        expect(index, greaterThan(-1));
        expect(source.substring(index, index + 400), contains('try {'));
      }
    });
  });
}
