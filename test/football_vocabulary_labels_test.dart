import 'dart:io';

import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/utils/football_vocabulary_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le vocabulaire footballistique restait en français quand l'application
/// passait en anglais.
///
/// Le modèle portait pourtant `labelEn` depuis le début. Ce n'était pas une
/// traduction manquante, c'était 46 points d'appel qui lisaient `labelFr`
/// sans condition, répartis dans onze fichiers, deux seulement respectant la
/// langue avec un ternaire écrit sur place. Un défaut de ce genre ne se
/// corrige pas une fois : il revient au premier écran ajouté, parce que
/// `labelFr` reste à portée de main et se compile sans rien dire.
///
/// D'où le garde-fou ci-dessous, qui compte plus que les assertions de
/// traduction : il interdit la lecture directe plutôt que de vérifier les
/// endroits qu'on connaît déjà.
void main() {
  group('les libellés suivent la langue de l\'interface', () {
    late AppLocalizations french;
    late AppLocalizations english;

    setUp(() async {
      french = await AppLocalizations.delegate.load(const Locale('fr'));
      english = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('poste', () {
      expect(FootballPosition.goalkeeper.label(french), 'Gardien');
      expect(FootballPosition.goalkeeper.label(english), 'Goalkeeper');
      expect(
        FootballPosition.attackingMidfielder.label(french),
        'Milieu offensif',
      );
      expect(
        FootballPosition.attackingMidfielder.label(english),
        'Attacking midfielder',
      );
    });

    test('pied fort, statut contractuel et niveau de club', () {
      for (final foot in StrongFoot.values) {
        expect(foot.label(french), foot.labelFr);
        expect(foot.label(english), foot.labelEn);
      }
      for (final status in ContractStatus.values) {
        expect(status.label(french), status.labelFr);
        expect(status.label(english), status.labelEn);
      }
      for (final level in ClubLevel.values) {
        expect(level.label(french), level.labelFr);
        expect(level.label(english), level.labelEn);
      }
    });

    /// Une traduction qui recopie le français n'est pas une traduction, et
    /// elle passerait le test précédent sans rien dire.
    test('aucun poste ne reste en français côté anglais', () {
      final untranslated = FootballPosition.values
          .where((position) => position.labelEn == position.labelFr)
          .map((position) => position.code)
          .toList();

      expect(
        untranslated,
        isEmpty,
        reason:
            'Ces postes portent le même libellé dans les deux langues : '
            '$untranslated. Soit la traduction manque, soit elle recopie le '
            'français.',
      );
    });
  });

  group('la recherche porte les deux langues', () {
    test('un poste rend son libellé français et anglais', () {
      expect(
        FootballPosition.goalkeeper.searchLabels,
        containsAll(<String>['Gardien', 'Goalkeeper']),
      );
    });

    test('matchesAnyLabel trouve la saisie dans l\'une ou l\'autre', () {
      final labels = FootballPosition.centreBack.searchLabels;

      expect(matchesAnyLabel(labels, 'défenseur central'), isTrue);
      expect(matchesAnyLabel(labels, 'centre-back'), isTrue);
      expect(matchesAnyLabel(labels, 'gardien'), isFalse);
    });
  });

  test('aucun fichier de lib/ ne lit labelFr ou labelEn directement', () {
    // Les deux seuls fichiers autorisés : celui qui les déclare, et celui qui
    // les expose derrière `label(l10n)`.
    const allowed = <String>{
      'lib/models/football_vocabulary.dart',
      'lib/utils/football_vocabulary_labels.dart',
    };

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final path = entity.path.replaceAll(r'\', '/');
      if (allowed.any(path.endsWith)) continue;

      final source = entity.readAsStringSync();
      for (final (index, line) in source.split('\n').indexed) {
        if (line.contains('.labelFr') || line.contains('.labelEn')) {
          offenders.add('$path:${index + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Ces lignes figent une langue : $offenders. Utilisez '
          '`label(l10n)`, ou `labelForCurrentLocale` sans contexte, ou '
          '`searchLabels` pour une mise en correspondance de saisie. Voir '
          'lib/utils/football_vocabulary_labels.dart.',
    );
  });
}
