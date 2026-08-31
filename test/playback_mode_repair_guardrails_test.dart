import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The repair for `playback.mode` must stay reachable, and must stay narrow.
///
/// Two separate risks, and the second is the dangerous one.
///
/// Reachable: `check-deployed-firebase-rules.mjs` sat in this repo referenced
/// by no npm script, no gate and no runbook until 2026-08-31. A tool an
/// operator has to remember is not a control, which is the reason
/// `backend_parity_gate_guardrails_test.dart` exists — this holds the same
/// line for the same reason.
///
/// Narrow: the sibling `backfill-playback-contract.js` rebuilds a whole
/// contract and collapses `sources` to a single canonical entry, which
/// `selectCanonicalMp4Source` picks at 480p or below. Pointing it at the two
/// multi-rendition videos in adfoot-production would delete their 1080p
/// master and leave every viewer — recruiter on fibre included — on 480p.
/// The repair therefore writes one field path and nothing else, and that is
/// the property worth locking down.
void main() {
  test('the repair is reachable as an npm script, both ways', () {
    final packageJson =
        jsonDecode(_read('package.json')) as Map<String, dynamic>;
    final scripts = (packageJson['scripts'] as Map).cast<String, dynamic>();

    expect(scripts, contains('playback:mode:check:production'));
    expect(scripts, contains('playback:mode:repair:production'));

    // The check must stay read-only: a "check" that writes is a trap.
    expect(scripts['playback:mode:check:production'], isNot(contains('--apply')));
    expect(scripts['playback:mode:repair:production'], contains('--apply'));

    for (final name in const <String>[
      'playback:mode:check:production',
      'playback:mode:repair:production',
    ]) {
      expect(scripts[name], contains('repair-playback-mode.mjs'));
    }
  });

  test('the release checklist names the check', () {
    expect(
      _read('docs/checklists/android-release-checklist.md'),
      contains('playback:mode:check:production'),
    );
  });

  group('the repair stays narrow', () {
    final script = _read('scripts/repair-playback-mode.mjs');

    test('it writes only the mode field path', () {
      expect(script, contains("'playback.mode': entry.expected"));

      // Any other write to the document is how the 1080p master would be
      // lost. There must be exactly one update call, on that one path, and no
      // document write of any other kind. (`args.set` is the local arg map,
      // hence matching on the Firestore reference rather than on `.set(`.)
      expect('.update('.allMatches(script).length, 1);
      expect(script, isNot(contains('ref.set(')));
      expect(script, isNot(contains('.delete(')));
    });

    test('it never touches the sources array', () {
      // Reading `playback.sources` to count renditions is the whole job;
      // assigning to it is not.
      expect(script, isNot(contains('sources:')));
      expect(script, isNot(contains("'playback.sources'")));
    });

    test('it applies the same rule as the optimizer', () {
      // `buildPlaybackContract` in functions/src/index.ts is the authority.
      // Two copies of a rule is how a contract and its producer drift apart —
      // which is the very bug being repaired here.
      expect(
        script,
        contains(
          "return sources.length > 1 ? 'multi_rendition_mp4' : 'mp4_only';",
        ),
      );
      expect(
        _read('functions/src/index.ts'),
        contains(
          'mode: mp4Sources.length > 1 ? "multi_rendition_mp4" : "mp4_only",',
        ),
      );
    });

    test('it is a dry run unless asked otherwise', () {
      expect(script, contains("const apply = args.has('apply');"));
      expect(script, contains('Dry run: nothing was written.'));
    });
  });
}
