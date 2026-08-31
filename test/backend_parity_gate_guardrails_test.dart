import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The deployed backend has to be the backend this checkout describes, and
/// the two halves of that question fail very differently.
///
/// Rules drift is loud: the build gets permission-denied and somebody reports
/// it the same day. Index drift is silent — Firestore answers `code 9
/// FAILED_PRECONDITION`, the repository catches it like any other failure,
/// and the screen just looks empty. `VideoRepository` documents exactly that
/// risk for the `approvedAt` feed ordering and carries a runtime downgrade
/// because of it.
///
/// A comparator for rules already existed and was referenced by nothing: no
/// npm script, no gate, no runbook. A tool an operator has to remember is not
/// a control, which is the whole reason these assertions exist.
void main() {
  test('both drift comparators are reachable as npm scripts', () {
    final packageJson =
        jsonDecode(_read('package.json')) as Map<String, dynamic>;
    final scripts = (packageJson['scripts'] as Map).cast<String, dynamic>();

    expect(scripts, contains('firebase:rules:check:production'));
    expect(scripts, contains('firestore:indexes:check:production'));
    expect(scripts, contains('backend:parity:check:production'));

    expect(
      scripts['firebase:rules:check:production'],
      contains('check-deployed-firebase-rules.mjs'),
    );
    expect(
      scripts['firestore:indexes:check:production'],
      contains('check-deployed-firestore-indexes.mjs'),
    );
  });

  test('the parity gate runs both comparators, not just one', () {
    final gate = _read('scripts/check-backend-parity.ps1');

    expect(gate, contains('check-deployed-firebase-rules.mjs'));
    expect(gate, contains('check-deployed-firestore-indexes.mjs'));

    // Both have to run and both have to be able to fail the gate. Stopping at
    // the first failure would hide the second one behind it, and the pair is
    // most useful precisely when a deploy was half done.
    expect(gate, contains('foreach (\$check in \$checks)'));
    expect(gate, contains('\$failures += \$check.Name'));
    expect(gate, contains('exit 1'));
  });

  test('the coherence gate calls the parity gate when the backend is in scope',
      () {
    final coherenceGate = _read('scripts/run-product-coherence-gate.ps1');

    expect(coherenceGate, contains('IncludeBackendGate'));
    expect(coherenceGate, contains('check-backend-parity.ps1'));

    // The parity check has to precede the scheduler check: "is the deployed
    // backend the right one" is not answerable from "did a scheduled function
    // run recently", and the cheaper, more discriminating check goes first.
    expect(
      coherenceGate.indexOf('check-backend-parity.ps1'),
      lessThan(coherenceGate.indexOf('check-production-backend-gate.ps1')),
    );
  });

  test('a building index is treated as a missing one', () {
    final checker = _read('scripts/check-deployed-firestore-indexes.mjs');

    // An index in state CREATING does not serve queries. Reporting it as
    // deployed would clear a release gate for a backend that still answers
    // code 9 to every query that needs it.
    expect(checker, contains("state !== 'READY'"));
    expect(checker, contains('notReady'));

    // TTL is declared in firestore.indexes.json as fieldOverrides, but a
    // declared policy and an armed one are different facts, and the two
    // collections it covers are the ones that grow without a ceiling.
    expect(checker, contains('ttlConfig'));
    expect(checker, contains("state !== 'ACTIVE'"));
  });

  test('every index declared for production is still declared in one file',
      () {
    final indexes =
        jsonDecode(_read('firestore.indexes.json')) as Map<String, dynamic>;
    final declared = (indexes['indexes'] as List).cast<Map<String, dynamic>>();

    // The feed ordering key. VideoRepository downgrades to updatedAt when it
    // is missing, so losing this entry costs no error anywhere — only the
    // ordering the product depends on, silently.
    expect(
      declared.any(
        (index) =>
            index['collectionGroup'] == 'videos' &&
            (index['fields'] as List).any(
              (field) =>
                  (field as Map)['fieldPath'] == 'approvedAt',
            ),
      ),
      isTrue,
      reason:
          'videos(status, approvedAt) backs the feed ordering; removing it '
          'downgrades the whole feed with no error surfaced anywhere.',
    );

    final overrides =
        (indexes['fieldOverrides'] as List).cast<Map<String, dynamic>>();
    final ttlCollections = overrides
        .where((override) => override['ttl'] == true)
        .map((override) => override['collectionGroup'])
        .toSet();

    expect(ttlCollections, containsAll(<String>['client_logs',
      'video_action_logs']));
  });
}
