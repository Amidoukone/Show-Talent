import 'dart:io';

import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/models/org_football_profile.dart';
import 'package:adfoot/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The club and agent halves of the profile redesign.
///
/// Same two guarantees as the player model: a document can never break a
/// screen, and the model agrees with `firestore.rules` about what the owner
/// may write — `changesOnly()` fails the whole save when they disagree, not
/// just the offending field.
void main() {
  group('a club document parses tolerantly', () {
    test('an empty map is an empty profile', () {
      final club = ClubFootballProfile.fromUserMap(<String, dynamic>{});

      expect(club.isEmpty, isTrue);
      expect(club.ageCategories, isEmpty);
    });

    test('unreadable values are absent, never exceptions', () {
      final club = ClubFootballProfile.fromUserMap(<String, dynamic>{
        'clubLevel': 'super-pro',
        'clubAgeCategories': 'U19',
        'clubFederationId': '   ',
      });

      expect(club.isEmpty, isTrue);
    });

    test('a full document parses to typed values', () {
      final club = ClubFootballProfile.fromUserMap(<String, dynamic>{
        'clubLevel': 'academy',
        'clubAgeCategories': <String>['U17', 'U19', 'U17'],
        'clubFederationId': 'FIF-2291',
      });

      expect(club.level, ClubLevel.academy);
      expect(club.ageCategories, <AgeCategory>[
        AgeCategory.u17,
        AgeCategory.u19,
      ]);
      expect(club.federationId, 'FIF-2291');
    });
  });

  group('an agent document parses tolerantly', () {
    test('a country name is refused, a code is kept', () {
      // Writing "France" in full is what this model replaces; accepting it
      // would let free text back in through the cellar.
      final agent = AgentFootballProfile.fromUserMap(<String, dynamic>{
        'agentLicenceCountry': 'France',
        'agentCountries': <String>['France', 'fr', 'FR', 'CI'],
      });

      expect(agent.licenceCountry, isNull);
      expect(agent.countries, <String>['FR', 'CI']);
    });

    test('the countries list is bounded', () {
      final agent = AgentFootballProfile.fromUserMap(<String, dynamic>{
        'agentCountries': List<String>.generate(
          20,
          (index) => String.fromCharCodes(<int>[65 + index ~/ 26, 65 + index % 26]),
        ),
      });

      expect(
        agent.countries.length,
        lessThanOrEqualTo(AgentFootballProfile.maxCountries),
      );
    });

    test('a licence number alone still counts as a profile', () {
      // It is the one publicly verifiable field in the product: a profile that
      // carries only it is still worth something.
      final agent = AgentFootballProfile.fromUserMap(<String, dynamic>{
        'agentLicenceNumber': 'FFF-AG-1180',
      });

      expect(agent.isNotEmpty, isTrue);
    });
  });

  group('AppUser exposes the right profile per role', () {
    AppUser user(String role, Map<String, dynamic> fields) =>
        AppUser.fromMap(<String, dynamic>{
          'uid': 'u1',
          'nom': 'Test',
          'role': role,
          ...fields,
        });

    test('a club with a level has an advanced profile', () {
      final club = user('club', <String, dynamic>{'clubLevel': 'pro'});

      expect(club.club.level, ClubLevel.professional);
      expect(club.hasAdvancedProfile, isTrue);
    });

    test('an agent with a licence has an advanced profile', () {
      final agent = user('agent', <String, dynamic>{
        'agentLicenceNumber': 'FFF-AG-1180',
      });

      expect(agent.hasAdvancedProfile, isTrue);
    });

    test('a legacy clubProfile document reads as empty', () {
      // `structureType` / `categories` free text is not migrated: the accounts
      // are test accounts, and guessing is worse than an empty field.
      final club = user('club', <String, dynamic>{
        'clubProfile': <String, dynamic>{
          'structureType': 'academy',
          'categories': <String>['U19'],
        },
      });

      expect(club.club.isEmpty, isTrue);
      expect(club.hasAdvancedProfile, isFalse);
    });

    test('roles do not read each other s fields', () {
      final club = user('club', <String, dynamic>{
        'agentLicenceNumber': 'FFF-AG-1180',
      });

      // The document carries an agent field; the club profile stays empty, so
      // `hasAdvancedProfile` must not turn true for the wrong reason.
      expect(club.club.isEmpty, isTrue);
      expect(club.hasAdvancedProfile, isFalse);
    });
  });

  group('the models and firestore.rules agree', () {
    final rules = _read('firestore.rules');

    String ownerWhitelist() {
      final start = rules.indexOf('function canUpdateOwnProfile()');
      expect(start, greaterThan(-1), reason: 'canUpdateOwnProfile() vanished');
      final end = rules.indexOf('ownerCvUrlChangeIsSafe()', start);
      expect(end, greaterThan(start));
      return rules.substring(start, end);
    }

    test('every writable field is allowed by the owner whitelist', () {
      final whitelist = ownerWhitelist();

      for (final field in <String>[
        ...ClubFootballProfile.writableFieldPaths,
        ...AgentFootballProfile.writableFieldPaths,
      ]) {
        expect(
          whitelist,
          contains('"$field"'),
          reason: '$field is written by toPatch() but rejected by the rules',
        );
      }
    });

    test('changing a club or agent fact invalidates a verified profile', () {
      // A club that gets verified and then changes its level, or an agent that
      // swaps its licence number, would otherwise keep a badge certifying a
      // file that no longer exists.
      final start = rules.indexOf('function ownerProfileTrustFieldsChanged()');
      expect(start, greaterThan(-1));
      final trustList = rules.substring(start, rules.indexOf(']', start));

      for (final field in <String>[
        ...ClubFootballProfile.writableFieldPaths,
        ...AgentFootballProfile.writableFieldPaths,
      ]) {
        expect(trustList, contains('"$field"'), reason: field);
      }
    });
  });
}
