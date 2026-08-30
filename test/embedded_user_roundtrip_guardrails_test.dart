import 'package:adfoot/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

/// The embedded-user map must survive a model round trip byte for byte.
///
/// Offer candidates and event participants are stored as embedded maps, and
/// the Firestore rules now require a write to carry every *other* row over
/// unchanged (`hasAll`) — that is what stops one player deleting a rival's
/// application. The rule compares the maps by value.
///
/// So any client that re-serialises an untouched row through
/// `AppUser.fromEmbeddedMap` → `toEmbeddedMap` and produces even a slightly
/// different map turns a legitimate registration into `permission-denied`.
/// EventRepository was doing exactly that until 2026-08-29 and now carries the
/// stored maps verbatim, like OfferRepository always has — but a build already
/// on testers' phones still re-serialises.
///
/// These tests are what says whether the hardened rules can be deployed ahead
/// of the client build, or must ship with it.
void main() {
  Map<String, dynamic> storedRow({
    String uid = 'RuLh6bcq6fhHYCD4chuu6ryI8Cl2',
    String role = 'joueur',
  }) {
    // The exact shape toEmbeddedMap() writes, which is therefore the exact
    // shape adfoot-production holds for its offer candidates and event
    // participants.
    return <String, dynamic>{
      'uid': uid,
      'nom': 'Adama Tambour',
      'role': role,
      'photoProfil': 'https://example.invalid/p.jpg',
      'estActif': true,
      'authDisabled': false,
      'emailVerified': true,
      'createdByAdmin': true,
      'profileVerified': false,
      'profileVerificationStatus': 'pending',
      'nomClub': null,
      'ligue': null,
      'entreprise': null,
      'team': null,
      'profilePublic': true,
      'allowMessages': true,
    };
  }

  group('embedded user maps round-trip unchanged', () {
    test('a stored row survives fromEmbeddedMap -> toEmbeddedMap', () {
      final stored = storedRow();
      final roundTripped = AppUser.fromEmbeddedMap(stored).toEmbeddedMap();

      expect(
        roundTripped,
        equals(stored),
        reason:
            'a re-serialised row that differs from the stored one breaks the '
            'hasAll() clause in canApplyToOffer / canJoinEvent',
      );
    });

    test('the key set is stable in both directions', () {
      final stored = storedRow();
      final roundTripped = AppUser.fromEmbeddedMap(stored).toEmbeddedMap();

      expect(
        roundTripped.keys.toSet(),
        equals(stored.keys.toSet()),
        reason: 'an added or dropped key is enough to fail map equality',
      );
    });

    test('a row for each publisher role round-trips too', () {
      for (final role in const ['joueur', 'club', 'recruteur', 'agent', 'fan']) {
        final stored = storedRow(uid: 'uid_$role', role: role);
        expect(
          AppUser.fromEmbeddedMap(stored).toEmbeddedMap(),
          equals(stored),
          reason: 'role $role does not round-trip',
        );
      }
    });
  });
}
