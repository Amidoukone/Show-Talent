import 'dart:io';

import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/models/player_football_profile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The typed replacement for `playerProfile`.
///
/// Two families of guarantee matter here. The first is that a document can
/// never break a screen: every field parses tolerantly, and an unreadable
/// value is an absent one. The second is that the model and `firestore.rules`
/// agree on what the owner may write — they are two lists in two languages,
/// and `changesOnly()` fails the *whole* save when they disagree, not just the
/// offending field.
void main() {
  group('a document can never break a profile', () {
    test('an empty map parses to an empty profile', () {
      final profile = PlayerFootballProfile.fromUserMap(<String, dynamic>{});

      expect(profile.isEmpty, isTrue);
      expect(profile.positions, isEmpty);
      expect(profile.nationalities, isEmpty);
      expect(profile.primaryPosition, isNull);
    });

    test('unreadable values are absent, never exceptions', () {
      final profile = PlayerFootballProfile.fromUserMap(<String, dynamic>{
        'positionCodes': 'CB',
        'strongFoot': 'sideways',
        'contractStatus': <String>['free'],
        'currentClubLevel': 99,
        'heightCm': 'grand',
        'currentSeason': 'saison passée',
      });

      expect(profile.isEmpty, isTrue);
    });

    test('a full document parses to typed values', () {
      final profile = PlayerFootballProfile.fromUserMap(<String, dynamic>{
        'birthYear': 2007,
        'nationalities': <String>['ci', 'FR'],
        'positionCodes': <String>['CM', 'AM'],
        'strongFoot': 'left',
        'heightCm': 178,
        'weightKg': 70,
        'contractStatus': 'under_contract',
        'contractEndDate': Timestamp.fromDate(DateTime.utc(2028, 6, 30)),
        'currentClubName': 'ASEC Mimosas',
        'currentClubLevel': 'academy',
        'currentSeason': <String, dynamic>{
          'season': '2025-26',
          'competition': 'Ligue 1 CIV',
          'ageCategory': 'U19',
          'appearances': 22,
          'minutes': 1740,
          'goals': 6,
          'assists': 4,
        },
        'isSearchable': true,
      });

      expect(profile.birthYear, 2007);
      expect(profile.nationalities, <String>['CI', 'FR']);
      expect(profile.primaryPosition, FootballPosition.centralMidfielder);
      expect(profile.strongFoot, StrongFoot.left);
      expect(profile.contractStatus, ContractStatus.underContract);
      expect(profile.currentClubLevel, ClubLevel.academy);
      expect(profile.currentSeason?.ageCategory, AgeCategory.u19);
      expect(profile.currentSeason?.minutes, 1740);
      expect(profile.isSearchable, isTrue);
    });
  });

  group('the values are constrained, not merely stored', () {
    test('a height outside human range is refused', () {
      for (final value in <int>[0, 40, 300]) {
        final profile = PlayerFootballProfile.fromUserMap(<String, dynamic>{
          'heightCm': value,
        });
        expect(profile.heightCm, isNull, reason: '$value cm');
      }

      expect(
        PlayerFootballProfile.fromUserMap(<String, dynamic>{
          'heightCm': 178,
        }).heightCm,
        178,
      );
    });

    test('a nationality must be an ISO code, not a country name', () {
      // Writing "Côte d'Ivoire" in full is exactly what this model replaces.
      // Accepting it here would let free text back in through the cellar.
      final profile = PlayerFootballProfile.fromUserMap(<String, dynamic>{
        'nationalities': <String>['Côte d’Ivoire', 'CIV', 'ci', 'CI', 'FR'],
      });

      expect(profile.nationalities, <String>['CI', 'FR']);
    });

    test('nationalities stop at the declared maximum', () {
      final profile = PlayerFootballProfile.fromUserMap(<String, dynamic>{
        'nationalities': <String>['CI', 'FR', 'BE', 'ES'],
      });

      expect(
        profile.nationalities.length,
        PlayerFootballProfile.maxNationalities,
      );
    });

    test('a negative match count is absent rather than wrong', () {
      final profile = PlayerFootballProfile.fromUserMap(<String, dynamic>{
        'currentSeason': <String, dynamic>{'goals': -3, 'minutes': 900},
      });

      expect(profile.currentSeason?.goals, isNull);
      expect(profile.currentSeason?.minutes, 900);
    });

    test('at most three positions survive, in declared order', () {
      final profile = PlayerFootballProfile.fromUserMap(<String, dynamic>{
        'positionCodes': <String>['ST', 'LW', 'RW', 'AM'],
      });

      expect(profile.positions, <FootballPosition>[
        FootballPosition.striker,
        FootballPosition.leftWinger,
        FootballPosition.rightWinger,
      ]);
    });
  });

  group('what is written back', () {
    test('a contract end date is dropped when the status has none', () {
      // Keeping it after a move to "free agent" would let a recruiter believe
      // the player is still engaged somewhere.
      const profile = PlayerFootballProfile(
        contractStatus: ContractStatus.free,
      );
      final withDate = profile.copyWith(
        contractEndDate: DateTime.utc(2028, 6, 30),
      );

      expect(withDate.toPatch()['contractEndDate'], isNull);
    });

    test('it is kept when the status expects one', () {
      final profile = PlayerFootballProfile(
        contractStatus: ContractStatus.underContract,
        contractEndDate: DateTime.utc(2028, 6, 30),
      );

      expect(profile.toPatch()['contractEndDate'], isA<Timestamp>());
    });

    test('positions are written as codes, never as labels', () {
      const profile = PlayerFootballProfile(
        positions: <FootballPosition>[FootballPosition.centreBack],
      );

      expect(profile.toPatch()['positionCodes'], <String>['CB']);
    });

    test('the server-derived fields are never written by the client', () {
      final patch = PlayerFootballProfile.fromUserMap(<String, dynamic>{
        'birthYear': 2007,
        'isSearchable': true,
      }).toPatch();

      for (final field in PlayerFootballProfile.serverDerivedFieldPaths) {
        expect(patch, isNot(contains(field)), reason: field);
      }
    });
  });

  group('the model and firestore.rules agree', () {
    final rules = _read('firestore.rules');

    String ownerWhitelist() {
      final start = rules.indexOf('function canUpdateOwnProfile()');
      expect(start, greaterThan(-1), reason: 'canUpdateOwnProfile() vanished');
      final end = rules.indexOf('ownerCvUrlChangeIsSafe()', start);
      expect(end, greaterThan(start));
      return rules.substring(start, end);
    }

    test('every writable field is allowed by the owner whitelist', () {
      // `changesOnly()` rejects the entire write when one key is missing, so a
      // field absent here does not fail quietly — it makes saving the profile
      // impossible with a permission-denied.
      final whitelist = ownerWhitelist();

      for (final field in PlayerFootballProfile.writableFieldPaths) {
        expect(
          whitelist,
          contains('"$field"'),
          reason: '$field is written by toPatch() but rejected by the rules',
        );
      }
    });

    test('the server-derived fields are not writable by the owner', () {
      final whitelist = ownerWhitelist();

      for (final field in PlayerFootballProfile.serverDerivedFieldPaths) {
        expect(
          whitelist,
          isNot(contains('"$field"')),
          reason: '$field must be derived by the server, not declared by the '
              'account it describes',
        );
      }
    });

    test('changing a football fact invalidates a verified profile', () {
      // A player who gets verified and then changes nationality or position
      // would otherwise keep a badge certifying a file that no longer exists.
      final start = rules.indexOf('function ownerProfileTrustFieldsChanged()');
      expect(start, greaterThan(-1));
      final trustList = rules.substring(start, rules.indexOf(']', start));

      for (final field in const <String>[
        'nationalities',
        'positionCodes',
        'strongFoot',
        'contractStatus',
        'currentClubLevel',
      ]) {
        expect(trustList, contains('"$field"'), reason: field);
      }
    });
  });
}
