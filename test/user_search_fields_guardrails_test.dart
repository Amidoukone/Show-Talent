import 'dart:convert';
import 'dart:io';

import 'package:adfoot/models/player_football_profile.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The two fields no client may write, and the indexes that make them useful.
///
/// `birthYear` and `isSearchable` are deliberately absent from
/// `canUpdateOwnProfile`. That decision is only safe while something actually
/// fills them: a field declared server-derived and derived by nothing is a
/// field that stays null for ever, and a search that filters on it returns an
/// empty screen rather than an error.
void main() {
  final trigger = _read('functions/src/user_search_fields.ts');
  final index = _read('functions/src/index.ts');

  group('something actually derives the server-only fields', () {
    test('both triggers are deployed', () {
      expect(index, contains('deriveUserSearchFields'));
      expect(index, contains('deriveUserSearchFieldsFromContact'));
      expect(index, contains('from "./user_search_fields"'));
    });

    test('the private contact document has its own trigger', () {
      // `birthDate` lives in users/{uid}/private/contact. A write there never
      // fires the users/{uid} trigger, so without this one the public year
      // would go stale the moment somebody edits a date of birth from the
      // admin portal or a script.
      expect(trigger, contains('document: "users/{uid}/private/contact"'));
      expect(trigger, contains('document: "users/{uid}"'));
    });

    test('it writes those two fields and nothing else', () {
      expect(trigger, contains('userRef.update({birthYear, isSearchable})'));
      expect('.update('.allMatches(trigger).length, 1);
      expect(trigger, isNot(contains('.set(')));
      expect(trigger, isNot(contains('.delete(')));
    });

    test('the recursion guard is present', () {
      // The trigger writes to the document whose writes fire it. Without the
      // early return on unchanged values it would loop for ever, and the bill
      // would be the first thing to notice.
      expect(
        trigger,
        contains(
          'if (currentBirthYear === birthYear && '
          'currentIsSearchable === isSearchable) {',
        ),
      );
    });

    test('a birth date never becomes a public full date', () {
      // Only the year crosses over to the public document; the complete date
      // stays in the private subcollection.
      expect(trigger, contains('date.getUTCFullYear()'));
      expect(trigger, isNot(contains('birthDate:')));
    });
  });

  group('the client cannot write what the server derives', () {
    test('the derived fields stay out of the owner whitelist', () {
      final rules = _read('firestore.rules');
      final start = rules.indexOf('function canUpdateOwnProfile()');
      final end = rules.indexOf('ownerCvUrlChangeIsSafe()', start);
      final whitelist = rules.substring(start, end);

      for (final field in PlayerFootballProfile.serverDerivedFieldPaths) {
        expect(whitelist, isNot(contains('"$field"')), reason: field);
      }
    });
  });

  group('the search indexes are declarable', () {
    final declared =
        (jsonDecode(_read('firestore.indexes.json'))
                as Map<String, dynamic>)['indexes']
            as List<dynamic>;

    List<Map<String, dynamic>> userIndexes() => declared
        .cast<Map<String, dynamic>>()
        .where((index) => index['collectionGroup'] == 'users')
        .toList();

    test('no composite index carries two array fields', () {
      // Firestore refuses this at deploy time, and the refusal arrives long
      // after the code that assumed the index exists was written. A query
      // crossing positions and nationalities therefore needs two indexes and
      // two round trips, not one clever index.
      for (final index in userIndexes()) {
        final arrayFields = (index['fields'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((field) => field.containsKey('arrayConfig'))
            .length;

        expect(
          arrayFields,
          lessThanOrEqualTo(1),
          reason: 'index on ${index['fields']} would be rejected at deploy',
        );
      }
    });

    test('every search index is gated by isSearchable first', () {
      // Leading with the gate is what keeps a filtered search from scanning
      // accounts that must never appear in one — disabled, private, or
      // incomplete.
      final searchIndexes = userIndexes().where((index) {
        final paths = (index['fields'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((field) => field['fieldPath'])
            .toList();
        return paths.contains('isSearchable');
      });

      expect(searchIndexes, isNotEmpty);
      for (final index in searchIndexes) {
        final first =
            ((index['fields'] as List<dynamic>).first
                as Map<String, dynamic>)['fieldPath'];
        expect(first, 'isSearchable');
      }
    });

    test('the position and nationality filters are both indexed', () {
      final arrays = userIndexes()
          .expand((index) => (index['fields'] as List<dynamic>))
          .cast<Map<String, dynamic>>()
          .where((field) => field.containsKey('arrayConfig'))
          .map((field) => field['fieldPath'])
          .toSet();

      expect(arrays, containsAll(<String>['positionCodes', 'nationalities']));
    });
  });
}
