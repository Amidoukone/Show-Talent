import 'package:adfoot/models/offre.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Offre model parsing', () {
    test('uses fallback id and parses mixed date formats safely', () {
      final offre = Offre.fromMap(
        {
          'titre': 'Recrutement U19',
          'description': 'Recherche milieu offensif.',
          'dateDebut': Timestamp.fromDate(DateTime.utc(2026, 4, 1)),
          'dateFin': '2026-04-30T00:00:00.000Z',
          'dateCreation': 1775000000000,
          'recruteur': {
            'uid': 'recruteur-1',
            'nom': 'Club A',
            'email': 'club@example.com',
            'role': 'club',
          },
          'candidats': [
            {
              'uid': 'joueur-1',
              'nom': 'Joueur A',
              'email': 'joueur@example.com',
              'role': 'joueur',
            },
          ],
          'statut': 'ouverte',
        },
        fallbackId: 'offre-fallback-id',
      );

      expect(offre.id, 'offre-fallback-id');
      expect(offre.titre, 'Recrutement U19');
      expect(offre.description, 'Recherche milieu offensif.');
      expect(offre.dateDebut.year, 2026);
      expect(offre.dateFin.month, 4);
      expect(offre.dateCreation.millisecondsSinceEpoch, 1775000000000);
      expect(offre.recruteur.uid, 'recruteur-1');
      expect(offre.candidats.map((c) => c.uid), ['joueur-1']);
      expect(offre.statut, 'ouverte');
    });

    test('keeps defensive defaults when payload is incomplete', () {
      final offre = Offre.fromMap(
        {
          'id': 'offre-2',
          'titre': null,
          'description': null,
          'dateDebut': null,
          'dateFin': null,
          'dateCreation': null,
          'recruteur': null,
          'candidats': null,
        },
      );

      expect(offre.id, 'offre-2');
      expect(offre.titre, '');
      expect(offre.description, '');
      expect(offre.recruteur.uid, '');
      expect(offre.candidats, isEmpty);
      expect(offre.dateDebut, isA<DateTime>());
      expect(offre.dateFin, isA<DateTime>());
      expect(offre.dateCreation, isA<DateTime>());
      expect(offre.statut, 'ouverte');
    });
  });
}
