import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Extrait les chaines entre guillemets d'un bloc de `firestore.rules`.
Set<String> _rulesTrustFields(String rules) {
  final start = rules.indexOf('function ownerProfileTrustFieldsChanged()');
  expect(start, greaterThan(-1), reason: 'la fonction doit exister');
  final end = rules.indexOf(']', start);
  expect(end, greaterThan(start));

  final block = rules.substring(start, end);
  return RegExp(r'"([^"]+)"')
      .allMatches(block)
      .map((match) => match.group(1)!)
      .toSet();
}

/// Extrait les chaines d'un `static const Set<String> <nom> = { ... };`.
Set<String> _dartSet(String source, String name) {
  final start = source.indexOf('static const Set<String> $name = {');
  expect(start, greaterThan(-1), reason: '$name doit exister');
  final end = source.indexOf('};', start);
  expect(end, greaterThan(start));

  // Les commentaires sont retires avant l'extraction : une apostrophe
  // francaise (« n'etait », « l'ecriture ») ouvrirait une chaine et decalerait
  // l'appariement de toutes les suivantes.
  final block = source
      .substring(start, end)
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  return RegExp(r"'([^']+)'")
      .allMatches(block)
      .map((match) => match.group(1)!)
      .toSet();
}

void main() {
  group('le client joint la remise a zero exactement quand la regle l\'exige', () {
    final rules = _read('firestore.rules');
    final repository = _read('lib/services/users/profile_repository.dart');

    test('aucun champ de confiance des regles n\'est ignore par le client', () {
      // Le bug que ce test tient : `ownerProfileTrustFieldsChanged()` listait
      // les faits footballistiques types, `_trustSensitiveProfileKeys` ne les
      // listait pas. Or c'est cette liste-la qui decide si le client joint la
      // remise a zero de la verification a sa patch, et
      // `verifiedOwnerProfileChangeIsInvalidated()` refuse l'ecriture d'un
      // profil verifie qui n'en porte pas.
      //
      // Consequence, en production : un joueur verifie qui corrigeait son
      // poste, son club, son gabarit ou ses statistiques voyait sa sauvegarde
      // refusee, et le formulaire lui conseillait de se reconnecter.
      final trustFields = _rulesTrustFields(rules);
      final clientKeys = _dartSet(repository, '_trustSensitiveProfileKeys');

      expect(trustFields, isNotEmpty);
      expect(clientKeys, isNotEmpty);

      final missing = <String>[];
      for (final field in trustFields) {
        // Une cle imbriquee (`currentSeason.goals`) est couverte des lors que
        // le client connait son parent : c'est la map entiere qu'il envoie.
        final parent = field.split('.').first;
        if (!clientKeys.contains(field) && !clientKeys.contains(parent)) {
          missing.add(field);
        }
      }

      expect(
        missing,
        isEmpty,
        reason:
            'ces champs invalident la verification cote regles mais le client '
            'ne joint pas la remise a zero quand il les ecrit : $missing',
      );
    });

    test('les deux champs prives restent hors de la liste des regles', () {
      // `phone` et `birthDate` vivent dans `users/{uid}/private/contact` et
      // sont ecrits dans le meme WriteBatch. La regle du document parent n'a
      // donc pas a les couvrir -- mais le client, lui, doit les traiter comme
      // sensibles. L'ecart est voulu, et ce test dit qu'il est voulu.
      final trustFields = _rulesTrustFields(rules);
      final clientKeys = _dartSet(repository, '_trustSensitiveProfileKeys');

      for (final field in const <String>['phone', 'birthDate']) {
        expect(trustFields, isNot(contains(field)), reason: field);
        expect(clientKeys, contains(field), reason: field);
      }
    });
  });
}
