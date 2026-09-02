import 'dart:io';

import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/models/player_football_profile.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The same vocabulary exists twice: in Dart for the clients, in TypeScript for
/// the Functions. It has to.
///
/// The Admin SDK **bypasses firestore.rules entirely**, so for everything the
/// administration portal writes, `sanitizeManagedProfilePatch` is the only
/// validation left standing. That validation needs the code list on the server.
///
/// Two copies of a list drift. The failure is silent and one-directional: a
/// code the server accepts but the client does not know parses to null, so a
/// file loses its position — or its contract status, or its foot — with no
/// error anywhere. This test is the only thing standing between that and a
/// production database.
List<String> _codesFrom(String source, String constName) {
  final match = RegExp(
    'export const $constName = \\[(.*?)\\]',
    dotAll: true,
  ).firstMatch(source);

  expect(match, isNotNull, reason: '$constName vanished from the server list');

  return RegExp('"([^"]+)"')
      .allMatches(match!.group(1)!)
      .map((m) => m.group(1)!)
      .toList();
}

void main() {
  final server = _read('functions/src/football_vocabulary.ts');

  test('the position codes are identical on both sides', () {
    expect(
      _codesFrom(server, 'POSITION_CODES'),
      FootballPosition.values.map((position) => position.code).toList(),
    );
  });

  test('the strong foot codes are identical', () {
    expect(
      _codesFrom(server, 'STRONG_FOOT_CODES'),
      StrongFoot.values.map((foot) => foot.code).toList(),
    );
  });

  test('the contract status codes are identical', () {
    expect(
      _codesFrom(server, 'CONTRACT_STATUS_CODES'),
      ContractStatus.values.map((status) => status.code).toList(),
    );
  });

  test('the club level codes are identical', () {
    expect(
      _codesFrom(server, 'CLUB_LEVEL_CODES'),
      ClubLevel.values.map((level) => level.code).toList(),
    );
  });

  test('the age category codes are identical', () {
    expect(
      _codesFrom(server, 'AGE_CATEGORY_CODES'),
      AgeCategory.values.map((category) => category.code).toList(),
    );
  });

  test('the per-player bounds are identical', () {
    expect(
      server,
      contains('MAX_POSITION_CODES = ${FootballPosition.maxPerPlayer}'),
    );
  });

  test('the career bound is identical on both sides', () {
    // Deux bornes qui divergent, c'est un parcours tronque differemment selon
    // qu'il a ete enregistre par le joueur ou corrige par l'administration.
    expect(
      server,
      contains(
        'MAX_SEASON_HISTORY = ${PlayerFootballProfile.maxSeasonHistory}',
      ),
    );
  });

  group('the admin callable validates instead of trusting', () {
    final admin = _read('functions/src/admin_account_actions.ts');

    test('the football fields go through the closed lists', () {
      expect(admin, contains('applyFootballFields(patch, updates)'));
      expect(admin, contains('from "./football_vocabulary"'));
    });

    test('the dead free-text fields are no longer writable', () {
      // `position`, and the three free-text profile maps, are read by nobody
      // since the redesign. Leaving them writable would let an administrator
      // fill dead fields believing they were correcting a file.
      expect(admin, contains('const mapFields: string[] = [];'));

      final start = admin.indexOf('const stringFields = [');
      final end = admin.indexOf('];', start);
      final stringFields = admin.substring(start, end);
      expect(stringFields, isNot(contains('"position"')));
    });

    test('a season corrected by the portal goes through the same lists', () {
      // Le portail ne pouvait corriger ni la saison en cours ni le parcours :
      // un dossier aux statistiques fausses n'avait aucun recours, alors que
      // c'est exactement ce qu'un recruteur signale.
      expect(admin, contains('toSeasonRecord(patch["currentSeason"])'));
      expect(admin, contains('toSeasonHistory(patch["seasonHistory"])'));

      // Le SDK Admin ne voit pas firestore.rules : la categorie d'age et le
      // niveau de club doivent etre resolus contre les listes fermees ici, ou
      // nulle part.
      final vocabulary = _read('functions/src/football_vocabulary.ts');
      final start = vocabulary.indexOf('export function toSeasonRecord(');
      final end = vocabulary.indexOf('\n}', start);
      final body = vocabulary.substring(start, end);

      expect(body, contains('toCode(AGE_CATEGORY_CODES'));
      expect(body, contains('toCode(CLUB_LEVEL_CODES'));
    });

    test('the server-derived fields are not admin-writable either', () {
      // Written by hand they would be overwritten at the next trigger pass,
      // which reads as a bug rather than as the rule.
      final start = admin.indexOf('function applyFootballFields(');
      final end = admin.indexOf('\n}', start);
      final body = admin.substring(start, end);

      expect(body, isNot(contains('"birthYear"')));
      expect(body, isNot(contains('"isSearchable"')));
    });
  });
}
