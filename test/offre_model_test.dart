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

    test('supports legacy aliases for owner and timestamps', () {
      final offre = Offre.fromMap(
        {
          'title': 'Offre legacy',
          'details': 'Format historique',
          'createdAt': '2026-04-01T10:00:00.000Z',
          'endDate': 1775000000000,
          'ownerUid': 'club-legacy',
          'ownerName': 'Club Legacy',
          'ownerRole': 'club',
          'applications': [
            {
              'uid': 'joueur-legacy',
              'nom': 'Legacy Player',
              'email': 'legacy@example.com',
              'role': 'joueur',
            },
          ],
          'status': 'archived',
          'location': 'Bouake',
        },
        fallbackId: 'legacy-offer',
      );

      expect(offre.id, 'legacy-offer');
      expect(offre.titre, 'Offre legacy');
      expect(offre.description, 'Format historique');
      expect(offre.recruteur.uid, 'club-legacy');
      expect(offre.candidats.single.uid, 'joueur-legacy');
      expect(offre.statut, 'archivee');
      expect(offre.localisation, 'Bouake');
    });

    test('toMap stores recruiter and candidates as minimal embedded users', () {
      final offre = Offre.fromMap(
        {
          'id': 'offre-min',
          'titre': 'Scout lateral',
          'description': 'Recherche lateral moderne',
          'dateDebut': Timestamp.fromDate(DateTime.utc(2026, 4, 1)),
          'dateFin': Timestamp.fromDate(DateTime.utc(2026, 4, 30)),
          'dateCreation': Timestamp.fromDate(DateTime.utc(2026, 3, 15)),
          'recruteur': {
            'uid': 'club-embedded',
            'nom': 'Club Embedded',
            'email': 'club-embedded@example.com',
            'role': 'club',
            'offrePubliees': [
              {'id': 'nested-offer'}
            ],
          },
          'candidats': [
            {
              'uid': 'player-embedded',
              'nom': 'Player Embedded',
              'email': 'player-embedded@example.com',
              'role': 'joueur',
              'eventPublies': [
                {'id': 'nested-event'}
              ],
            },
          ],
        },
      );

      final map = offre.toMap();
      final recruteur = Map<String, dynamic>.from(map['recruteur'] as Map);
      final candidat =
          Map<String, dynamic>.from((map['candidats'] as List).single as Map);

      expect(recruteur['uid'], 'club-embedded');
      expect(recruteur.containsKey('offrePubliees'), isFalse);
      expect(candidat['uid'], 'player-embedded');
      expect(candidat.containsKey('eventPublies'), isFalse);
    });
  });
}
