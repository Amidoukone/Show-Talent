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

  group('the agency badge says only what is true right now', () {
    final now = DateTime(2026, 8, 30);

    AppUser buildUser({
      String role = 'joueur',
      Map<String, dynamic>? membership,
    }) {
      return AppUser.fromMap(<String, dynamic>{
        'uid': 'u1',
        'nom': 'Adama',
        'role': role,
        'membership': ?membership,
      });
    }

    test('an account with no record carries no badge', () {
      // The accounts already in production have no `membership` field: the
      // badge must be invisible for every one of them.
      expect(buildUser().isAgencyPlayerAt(now), isFalse);
    });

    test('a player the agency carries wears it', () {
      final user = buildUser(
        membership: <String, dynamic>{'tier': 'adfoot'},
      );

      expect(user.isAgencyPlayerAt(now), isTrue);
    });

    test('a player who pays for the services does not', () {
      // `external` is a customer, not someone the agency accompanies —
      // showing the same badge would sell the wrong thing to a recruiter.
      final user = buildUser(
        membership: <String, dynamic>{'tier': 'external'},
      );

      expect(user.isAgencyPlayerAt(now), isFalse);
    });

    test('a lapsed record stops showing it', () {
      final user = buildUser(
        membership: <String, dynamic>{
          'tier': 'adfoot',
          'validUntil': DateTime(2026, 1, 1).toIso8601String(),
        },
      );

      expect(user.membership.isAgencyPlayer, isTrue);
      expect(user.isAgencyPlayerAt(now), isFalse);
    });

    test('a club or an agent never wears a player badge', () {
      for (final role in <String>['club', 'agent', 'recruteur', 'fan']) {
        final user = buildUser(
          role: role,
          membership: <String, dynamic>{'tier': 'adfoot'},
        );

        expect(
          user.isAgencyPlayerAt(now),
          isFalse,
          reason: 'the badge speaks of a player, not of a $role',
        );
      }
    });

    test('the label and the rule are declared exactly once', () {
      final badge = _read('lib/widgets/ad_agency_badge.dart');

      expect(badge, contains("kAgencyPlayerBadgeLabel = 'Joueur agence'"));
      expect(badge, contains('user.isAgencyPlayerAt(DateTime.now())'));

      // Three surfaces show this badge. A second copy of the literal is how
      // two of them end up saying slightly different things.
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('ad_agency_badge.dart'))
          .where((file) => file.readAsStringSync().contains("'Joueur agence'"))
          .map((file) => file.path)
          .toList();

      expect(offenders, isEmpty);
    });

    test('every surface showing it goes through the shared rule', () {
      // The profile, the video search results and the contact directory:
      // a surface that tests `membership.tier` itself would keep showing the
      // badge on a lapsed record.
      for (final path in const <String>[
        'lib/screens/profile_screen_widgets.dart',
        'lib/screens/home_screen_search_sheet.dart',
        'lib/screens/select_user_screen.dart',
      ]) {
        expect(
          _read(path),
          contains('showsAgencyBadge('),
          reason: '$path must ask the shared rule',
        );
      }
    });

    test('no surface leaks the commercial details of the record', () {
      // The term and the internal reference belong to the administration.
      // Profiles and search results are read by visitors, so neither may
      // reach any of them.
      final surface = <String>[
        'lib/widgets/ad_agency_badge.dart',
        'lib/screens/profile_screen.dart',
        'lib/screens/profile_screen_widgets.dart',
        'lib/screens/home_screen_search_sheet.dart',
        'lib/screens/select_user_screen.dart',
      ].map(_read).join('\n');

      expect(surface, isNot(contains('membership.reference')));
      expect(surface, isNot(contains('membership.validUntil')));
    });
  });
}
