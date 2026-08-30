import 'dart:io';

import 'package:adfoot/models/membership.dart';
import 'package:adfoot/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('an account with no recorded membership is unchanged', () {
    // The whole point of shipping this mechanism dormant: the 17 accounts in
    // production carry no `membership` field, and none of them may behave
    // differently the day this build reaches them.
    test('a user document without the field parses to none', () {
      final user = AppUser.fromMap(<String, dynamic>{
        'uid': 'u1',
        'nom': 'Adama',
        'role': 'joueur',
      });

      expect(user.membership.tier, MembershipTier.none);
      expect(user.membership.isRecorded, isFalse);
      expect(user.membership.isAgencyPlayer, isFalse);
    });

    test('none is not the same thing as expired', () {
      // A gate that treats "no record" and "lapsed" alike would lock out every
      // existing account the moment it ships.
      expect(Membership.none.isRecorded, isFalse);
      expect(Membership.none.isActiveAt(DateTime(2026, 8, 29)), isFalse);

      const lapsed = Membership(tier: MembershipTier.external);
      expect(lapsed.isRecorded, isTrue);
    });

    test('a malformed field never breaks profile loading', () {
      for (final raw in <Object?>[
        null,
        'adfoot',
        42,
        <String>['adfoot'],
        <String, dynamic>{'tier': 99},
        <String, dynamic>{'tier': 'gold'},
      ]) {
        final user = AppUser.fromMap(<String, dynamic>{
          'uid': 'u1',
          'nom': 'Adama',
          'role': 'joueur',
          'membership': raw,
        });
        expect(user.membership.tier, MembershipTier.none);
      }
    });
  });

  group('the two populations are distinguished', () {
    test('an agency player is recorded, without a term', () {
      final user = AppUser.fromMap(<String, dynamic>{
        'uid': 'u1',
        'nom': 'Adama',
        'role': 'joueur',
        'membership': <String, dynamic>{'tier': 'adfoot'},
      });

      expect(user.membership.tier, MembershipTier.adfoot);
      expect(user.membership.isAgencyPlayer, isTrue);
      expect(user.membership.validUntil, isNull);
      // No term: an agency player is tied by contract, not by a period.
      expect(user.membership.isActiveAt(DateTime(2099)), isTrue);
    });

    test('an external entitlement lapses on its date', () {
      final user = AppUser.fromMap(<String, dynamic>{
        'uid': 'u1',
        'nom': 'Adama',
        'role': 'joueur',
        'membership': <String, dynamic>{
          'tier': 'external',
          'validUntil': '2026-12-31T00:00:00.000Z',
        },
      });

      expect(user.membership.tier, MembershipTier.external);
      expect(user.membership.isAgencyPlayer, isFalse);
      expect(user.membership.isActiveAt(DateTime.utc(2026, 6, 1)), isTrue);
      expect(user.membership.isActiveAt(DateTime.utc(2027, 1, 1)), isFalse);
    });

    test('the French spelling is accepted too', () {
      expect(Membership.parseTier('externe'), MembershipTier.external);
      expect(Membership.parseTier('  ADFOOT  '), MembershipTier.adfoot);
    });
  });

  group('the entitlement stays out of the places that would break', () {
    // The embedded map is copied verbatim into offer candidates and event
    // participants, and the Firestore rules compare those rows by value. A new
    // key would make a re-serialised row differ from the stored one and turn a
    // legitimate application into permission-denied.
    test('membership never leaks into the embedded user map', () {
      final user = AppUser.fromMap(<String, dynamic>{
        'uid': 'u1',
        'nom': 'Adama',
        'role': 'joueur',
        'membership': <String, dynamic>{'tier': 'adfoot'},
      });

      expect(user.toEmbeddedMap().containsKey('membership'), isFalse);
    });

    test('the client can never write it', () {
      final rules = _read('firestore.rules');
      final allowlist = rules.indexOf('function canUpdateOwnProfile()');
      expect(allowlist, isNonNegative);

      final body = rules.substring(allowlist, allowlist + 2600);
      expect(
        body,
        isNot(contains('"membership"')),
        reason: 'an account that can grant itself an entitlement is not a '
            'business model',
      );
      expect(rules, isNot(contains('canUpdateOwnMembership')));
    });
  });

  group('no price ever enters the platform', () {
    // The Play Console declaration says this app has no in-app purchases, and
    // that stays true only while the app shows no price, offers no way to pay
    // and links to none. Payment happens at the agency; the callable records
    // the outcome and nothing else.
    test('the admin callable takes no amount', () {
      final actions = _read('functions/src/admin_account_actions.ts');
      final start = actions.indexOf('export const setManagedAccountMembership');
      expect(start, isNonNegative);

      final body = actions.substring(start);
      for (final forbidden in <String>[
        'amount',
        'price',
        'currency',
        'montant',
      ]) {
        expect(
          body.toLowerCase(),
          isNot(contains('"$forbidden"')),
          reason: 'a price inside the platform breaks the Play declaration',
        );
      }
    });

    test('the mobile app carries no payment surface', () {
      final lib = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      final offenders = <String>[];
      for (final file in lib) {
        final content = file.readAsStringSync().toLowerCase();
        for (final marker in <String>[
          'in_app_purchase',
          'billingclient',
          'stripe',
          'paypal',
          'play billing',
        ]) {
          if (content.contains(marker)) offenders.add('${file.path}: $marker');
        }
      }

      expect(offenders, isEmpty);
    });
  });
}
