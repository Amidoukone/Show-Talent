import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The administration can now correct a date of birth, and that is the one
/// correction that decides whether a file exists for a recruiter at all:
/// `birthYear` is derived from it, and `computeIsSearchable` refuses a null
/// year. Before this, a player whose date was missing or wrong could only be
/// repaired by the player, from their own phone.
///
/// Three things have to stay true, and none of them is visible from the
/// portal's side of the wire.
void main() {
  final admin = _read('functions/src/admin_account_actions.ts');
  final derivation = _read('functions/src/user_search_fields.ts');

  String _birthDateBranch() {
    final start = admin.indexOf('if ("birthDate" in patch) {');
    expect(start, greaterThan(0), reason: 'the birthDate branch vanished');
    return admin.substring(start, admin.indexOf('\n  }', start));
  }

  test('the date lands in the private contact document, never on the file', () {
    // The full date is contact data. Only the year, derived by the trigger,
    // reaches the public document — writing the date into the patch that goes
    // to users/{uid} would publish a player's date of birth to every reader.
    expect(admin, contains('contactUpdates["birthDate"]'));
    expect(admin, contains('delete mainDocUpdates["birthDate"]'));
  });

  test('one function decides what a usable date is, on both sides', () {
    // A date the callable accepts but the trigger refuses derives no year, and
    // the profile then sits in no search at all — invisible, with nothing
    // saying why. The bounds must therefore exist in exactly one place.
    expect(derivation, contains('export function toBirthYear('));
    expect(derivation, contains('export const MIN_BIRTH_YEAR = 1930;'));
    expect(derivation, contains('year < MIN_BIRTH_YEAR'));
    expect(
      admin,
      contains('import {MIN_BIRTH_YEAR, toBirthYear} from "./user_search_fields"'),
    );
    expect(admin, contains('if (toBirthYear(date) === null) return null;'));
    expect(
      admin,
      isNot(contains('1930')),
      reason: 'the year bound was copied instead of being imported — even in '
          'the error message, which would then be free to state a bound that '
          'is no longer applied',
    );
  });

  test('an unusable date is refused out loud', () {
    // Every other invalid field in this sanitiser is dropped in silence. This
    // one must not be: the correction exists to make an invisible file
    // findable, and a silent failure would leave the administration believing
    // it succeeded.
    final branch = _birthDateBranch();

    expect(branch, contains('new HttpsError('));
    expect(branch, contains('"invalid-argument"'));
    // Clearing stays possible: a date that was invented is better removed than
    // kept, and the trigger reads a null year the same way.
    expect(branch, contains('if (rawBirthDate === null) {'));
  });

  test('correcting the date drops a verification badge', () {
    // The age is a fact a recruiter takes on trust. Moving it while the file
    // stays marked "Vérifié par Adfoot" would put the badge behind a figure
    // nobody re-checked.
    final start = admin.indexOf('const TRUST_SENSITIVE_PROFILE_FIELDS = [');
    final trustList = admin.substring(start, admin.indexOf('];', start));

    expect(trustList, contains('"birthDate"'));
  });

  test('the stored shape stays the one the mobile client writes', () {
    // The client writes a Timestamp. Storing an ISO string from the portal
    // would work — toBirthYear tolerates both — and would quietly leave the
    // field with two types depending on who last touched it.
    expect(admin, contains('return Timestamp.fromDate(date);'));
  });
}
