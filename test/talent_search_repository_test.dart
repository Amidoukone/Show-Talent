import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/services/users/talent_search_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// The search a recruiter actually runs.
///
/// This is where the whole redesign becomes visible: closed vocabularies, flat
/// indexable fields and a server-derived `isSearchable` exist so that this
/// query can be asked of Firestore instead of of the phone.
Future<void> _addPlayer(
  FakeFirebaseFirestore firestore,
  String uid, {
  required bool isSearchable,
  List<String> positionCodes = const <String>[],
  List<String> nationalities = const <String>[],
  int? birthYear,
  bool openToOpportunities = false,
}) {
  return firestore.collection('users').doc(uid).set(<String, dynamic>{
    'uid': uid,
    'nom': 'Player $uid',
    'role': 'joueur',
    'isSearchable': isSearchable,
    'positionCodes': positionCodes,
    'nationalities': nationalities,
    'birthYear': ?birthYear,
    'openToOpportunities': openToOpportunities,
  });
}

void main() {
  group('the gate comes first', () {
    test('a file the server did not mark searchable never appears', () async {
      // Disabled, private or incomplete accounts are excluded by the index
      // itself, not filtered out afterwards. A recruiter must not be able to
      // reach an account that cannot answer.
      final firestore = FakeFirebaseFirestore();
      await _addPlayer(firestore, 'hidden', isSearchable: false,
          positionCodes: <String>['CM']);
      await _addPlayer(firestore, 'visible', isSearchable: true,
          positionCodes: <String>['CM']);

      final results = await TalentSearchRepository(firestore: firestore)
          .search(const TalentSearchQuery());

      expect(results.map((user) => user.uid), <String>['visible']);
    });
  });

  group('filtering by position', () {
    test('it returns any of the requested positions', () async {
      final firestore = FakeFirebaseFirestore();
      await _addPlayer(firestore, 'cb', isSearchable: true,
          positionCodes: <String>['CB']);
      await _addPlayer(firestore, 'lb', isSearchable: true,
          positionCodes: <String>['LB']);
      await _addPlayer(firestore, 'st', isSearchable: true,
          positionCodes: <String>['ST']);

      final results = await TalentSearchRepository(firestore: firestore)
          .search(
        const TalentSearchQuery(
          positions: <FootballPosition>[
            FootballPosition.centreBack,
            FootballPosition.leftBack,
          ],
        ),
      );

      expect(
        results.map((user) => user.uid).toSet(),
        <String>{'cb', 'lb'},
      );
    });

    test('a secondary position counts too', () async {
      // A player who declares CM then AM must be found by a club looking for
      // an AM: the array is the point, and the order is only a preference.
      final firestore = FakeFirebaseFirestore();
      await _addPlayer(firestore, 'versatile', isSearchable: true,
          positionCodes: <String>['CM', 'AM']);

      final results = await TalentSearchRepository(firestore: firestore)
          .search(
        const TalentSearchQuery(
          positions: <FootballPosition>[FootballPosition.attackingMidfielder],
        ),
      );

      expect(results.map((user) => user.uid), <String>['versatile']);
    });
  });

  group('filtering by age bracket', () {
    test('the bounds are inclusive', () async {
      final firestore = FakeFirebaseFirestore();
      await _addPlayer(firestore, 'y2005', isSearchable: true, birthYear: 2005);
      await _addPlayer(firestore, 'y2006', isSearchable: true, birthYear: 2006);
      await _addPlayer(firestore, 'y2008', isSearchable: true, birthYear: 2008);
      await _addPlayer(firestore, 'y2009', isSearchable: true, birthYear: 2009);

      final results = await TalentSearchRepository(firestore: firestore)
          .search(const TalentSearchQuery(bornFrom: 2006, bornUntil: 2008));

      expect(
        results.map((user) => user.uid).toSet(),
        <String>{'y2006', 'y2008'},
      );
    });
  });

  group('filtering by nationality', () {
    test('it is a server filter when no position is asked for', () async {
      final firestore = FakeFirebaseFirestore();
      await _addPlayer(firestore, 'ivorian', isSearchable: true,
          nationalities: <String>['CI']);
      await _addPlayer(firestore, 'malian', isSearchable: true,
          nationalities: <String>['ML']);

      final repository = TalentSearchRepository(firestore: firestore);
      const query = TalentSearchQuery(nationality: 'CI');

      expect(query.needsClientSideNationalityFilter, isFalse);
      final results = await repository.search(query);
      expect(results.map((user) => user.uid), <String>['ivorian']);
    });

    test('combined with a position, it still narrows the result', () async {
      // Firestore accepts only one array field per composite index, so the two
      // cannot both be server-side. The position goes to the server — it is
      // the more selective — and the nationality is applied to the page that
      // comes back, never to the collection.
      final firestore = FakeFirebaseFirestore();
      await _addPlayer(firestore, 'ci-cb', isSearchable: true,
          positionCodes: <String>['CB'], nationalities: <String>['CI']);
      await _addPlayer(firestore, 'ml-cb', isSearchable: true,
          positionCodes: <String>['CB'], nationalities: <String>['ML']);
      await _addPlayer(firestore, 'ci-st', isSearchable: true,
          positionCodes: <String>['ST'], nationalities: <String>['CI']);

      const query = TalentSearchQuery(
        positions: <FootballPosition>[FootballPosition.centreBack],
        nationality: 'CI',
      );
      expect(query.needsClientSideNationalityFilter, isTrue);

      final results = await TalentSearchRepository(firestore: firestore)
          .search(query);

      expect(results.map((user) => user.uid), <String>['ci-cb']);
    });

    test('a dual national is found under either passport', () async {
      final firestore = FakeFirebaseFirestore();
      await _addPlayer(firestore, 'dual', isSearchable: true,
          nationalities: <String>['CI', 'FR']);

      final repository = TalentSearchRepository(firestore: firestore);

      for (final code in <String>['CI', 'FR']) {
        final results =
            await repository.search(TalentSearchQuery(nationality: code));
        expect(results.map((user) => user.uid), <String>['dual'], reason: code);
      }
    });
  });

  group('availability', () {
    test('it narrows to players who said they are open', () async {
      final firestore = FakeFirebaseFirestore();
      await _addPlayer(firestore, 'open', isSearchable: true,
          openToOpportunities: true);
      await _addPlayer(firestore, 'closed', isSearchable: true);

      final results = await TalentSearchRepository(firestore: firestore)
          .search(const TalentSearchQuery(openToOpportunitiesOnly: true));

      expect(results.map((user) => user.uid), <String>['open']);
    });
  });

  group('the query stays within what an index can serve', () {
    test('a page is bounded', () async {
      final firestore = FakeFirebaseFirestore();
      for (var index = 0; index < TalentSearchRepository.pageSize + 5; index++) {
        await _addPlayer(firestore, 'p$index', isSearchable: true);
      }

      final results = await TalentSearchRepository(firestore: firestore)
          .search(const TalentSearchQuery());

      expect(results.length, TalentSearchRepository.pageSize);
    });

    test('never two array filters in one query', () async {
      // The failure this prevents arrives at deploy time, long after the code
      // that assumed the index exists was written.
      final repository = TalentSearchRepository(
        firestore: FakeFirebaseFirestore(),
      );

      final query = repository.buildQuery(
        const TalentSearchQuery(
          positions: <FootballPosition>[FootballPosition.centreBack],
          nationality: 'CI',
        ),
      );

      expect(query, isA<Query<Map<String, dynamic>>>());
    });

    test('an empty query is still gated', () {
      expect(const TalentSearchQuery().isEmpty, isTrue);
    });
  });
}
