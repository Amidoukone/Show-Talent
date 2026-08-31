import 'package:adfoot/models/football_vocabulary.dart';
import 'package:flutter_test/flutter_test.dart';

/// The vocabulary a recruiter filters on.
///
/// These tests guard the properties that break a search rather than a screen:
/// a duplicated code silently merges two positions, a list longer than ten
/// makes the commonest query impossible to express, and a parser that throws
/// on an unknown code turns a profile written by a newer client into a blank
/// screen.
void main() {
  group('codes are unique and queryable', () {
    test('no two positions share a code', () {
      final codes = FootballPosition.values.map((p) => p.code).toList();

      expect(codes.toSet().length, codes.length);
    });

    test('the position list fits in one array-contains-any query', () {
      // Firestore caps `array-contains-any` at 10 values. An eleventh position
      // would make "any defensive position" unexpressible in a single query —
      // the constraint is the reason the vocabulary stops where it does.
      expect(
        FootballPosition.values.length,
        lessThanOrEqualTo(FootballPosition.maxPerQuery),
      );
    });

    test('every vocabulary has unique, non-empty codes', () {
      final vocabularies = <String, List<String>>{
        'PositionGroup': PositionGroup.values.map((v) => v.code).toList(),
        'StrongFoot': StrongFoot.values.map((v) => v.code).toList(),
        'ContractStatus': ContractStatus.values.map((v) => v.code).toList(),
        'ClubLevel': ClubLevel.values.map((v) => v.code).toList(),
        'AgeCategory': AgeCategory.values.map((v) => v.code).toList(),
      };

      vocabularies.forEach((name, codes) {
        expect(codes.toSet().length, codes.length, reason: '$name has a duplicate');
        expect(
          codes.every((code) => code.trim().isNotEmpty),
          isTrue,
          reason: '$name has a blank code',
        );
      });
    });

    test('every position carries both labels and a group', () {
      for (final position in FootballPosition.values) {
        expect(position.labelFr.trim(), isNotEmpty, reason: position.code);
        expect(position.labelEn.trim(), isNotEmpty, reason: position.code);
      }

      // Every group must be reachable, or a coarse filter silently returns
      // nothing for it.
      expect(
        FootballPosition.values.map((p) => p.group).toSet(),
        PositionGroup.values.toSet(),
      );
    });
  });

  group('parsing never throws and never guesses', () {
    test('a known code resolves, whatever its casing or padding', () {
      expect(FootballVocabulary.position('CB'), FootballPosition.centreBack);
      expect(FootballVocabulary.position('cb'), FootballPosition.centreBack);
      expect(FootballVocabulary.position('  Cb  '), FootballPosition.centreBack);
    });

    test('an unknown code is null, not an exception', () {
      // A document written by a newer client, or by the admin portal, must not
      // turn a profile into a blank screen. A position we cannot read is a
      // position we do not show.
      expect(FootballVocabulary.position('SWEEPER'), isNull);
      expect(FootballVocabulary.position(''), isNull);
      expect(FootballVocabulary.position(null), isNull);
      expect(FootballVocabulary.position(42), isNull);
    });

    test('free text from the old profiles does not resolve', () {
      // The two advanced files in production hold "Défense" and "Attaquant".
      // They must not be silently mapped: "Défense" does not say whether the
      // player is central or a full-back, and writing a guess into a base we
      // present as qualified is worse than leaving it empty.
      expect(FootballVocabulary.position('Défense'), isNull);
      expect(FootballVocabulary.position('Attaquant'), isNull);
      expect(FootballVocabulary.position('défenseur central'), isNull);
    });

    test('each other vocabulary resolves its own codes', () {
      expect(FootballVocabulary.strongFoot('left'), StrongFoot.left);
      expect(
        FootballVocabulary.contractStatus('under_contract'),
        ContractStatus.underContract,
      );
      expect(FootballVocabulary.clubLevel('academy'), ClubLevel.academy);
      expect(FootballVocabulary.ageCategory('U19'), AgeCategory.u19);
      expect(FootballVocabulary.ageCategory('u19'), AgeCategory.u19);
    });
  });

  group('a declared position list stays readable', () {
    test('it keeps the declared order', () {
      expect(
        FootballVocabulary.positions(<String>['AM', 'CM']),
        <FootballPosition>[
          FootballPosition.attackingMidfielder,
          FootballPosition.centralMidfielder,
        ],
      );
    });

    test('it drops duplicates and unknowns without failing', () {
      expect(
        FootballVocabulary.positions(<Object>['CB', 'cb', 'SWEEPER', 'LB']),
        <FootballPosition>[
          FootballPosition.centreBack,
          FootballPosition.leftBack,
        ],
      );
    });

    test('it truncates beyond the per-player maximum', () {
      // A file carrying more than three came from a write that bypassed the
      // form; showing them all would suggest the limit is not real.
      expect(
        FootballVocabulary.positions(
          <String>['GK', 'CB', 'LB', 'RB', 'DM'],
        ).length,
        FootballPosition.maxPerPlayer,
      );
    });

    test('anything that is not a list is an empty list', () {
      expect(FootballVocabulary.positions(null), isEmpty);
      expect(FootballVocabulary.positions('CB'), isEmpty);
      expect(FootballVocabulary.positions(<String>[]), isEmpty);
    });
  });

  group('the vocabulary states facts, not self-assessment', () {
    test('a contract end date is expected only where it means something', () {
      expect(ContractStatus.underContract.expectsEndDate, isTrue);
      expect(ContractStatus.onLoan.expectsEndDate, isTrue);
      expect(ContractStatus.free.expectsEndDate, isFalse);
      expect(ContractStatus.amateur.expectsEndDate, isFalse);
    });

    test('only the senior category is open-ended', () {
      for (final category in AgeCategory.values) {
        if (category == AgeCategory.senior) {
          expect(category.maxAge, isNull);
        } else {
          expect(category.maxAge, isNotNull, reason: category.code);
        }
      }
    });
  });
}
