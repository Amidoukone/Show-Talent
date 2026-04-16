import 'package:adfoot/models/event.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Event model parsing', () {
    test('uses fallback id and parses mixed date formats safely', () {
      final event = Event.fromMap(
        {
          'titre': 'Detection regionale',
          'description': 'Journee de tests joueurs.',
          'dateDebut': Timestamp.fromDate(DateTime.utc(2026, 5, 12)),
          'dateFin': '2026-05-13T18:30:00.000Z',
          'createdAt': 1775000000000,
          'organisateur': {
            'uid': 'org-1',
            'nom': 'Club A',
            'email': 'club@example.com',
            'role': 'club',
          },
          'participants': [
            {
              'uid': 'player-1',
              'nom': 'Joueur A',
              'email': 'player@example.com',
              'role': 'joueur',
            },
          ],
          'statut': 'ferme',
          'lieu': 'Abidjan',
          'estPublic': true,
          'lastUpdated': Timestamp.fromDate(DateTime.utc(2026, 5, 1, 10)),
        },
        fallbackId: 'event-fallback-id',
      );

      expect(event.id, 'event-fallback-id');
      expect(event.titre, 'Detection regionale');
      expect(event.description, 'Journee de tests joueurs.');
      expect(event.dateDebut.year, 2026);
      expect(event.dateFin.month, 5);
      expect(event.createdAt.millisecondsSinceEpoch, 1775000000000);
      expect(event.organisateur.uid, 'org-1');
      expect(event.participants.map((p) => p.uid), ['player-1']);
      expect(event.statut, 'ferme');
      expect(event.lastUpdated, isNotNull);
    });

    test('keeps defensive defaults when payload is incomplete', () {
      final event = Event.fromMap({
        'id': 'event-2',
        'titre': null,
        'description': null,
        'dateDebut': null,
        'dateFin': null,
        'createdAt': null,
        'organisateur': null,
        'participants': null,
        'statut': null,
        'lieu': null,
        'estPublic': null,
      });

      expect(event.id, 'event-2');
      expect(event.titre, '');
      expect(event.description, '');
      expect(event.organisateur.uid, '');
      expect(event.participants, isEmpty);
      expect(event.dateDebut, isA<DateTime>());
      expect(event.dateFin, isA<DateTime>());
      expect(event.createdAt, isA<DateTime>());
      expect(event.statut, 'ouvert');
      expect(event.lieu, '');
      expect(event.estPublic, isTrue);
    });

    test('toMap writes canonical status', () {
      final event = Event.fromMap({
        'id': 'event-3',
        'titre': 'Test',
        'description': 'Test',
        'dateDebut': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
        'dateFin': Timestamp.fromDate(DateTime.utc(2026, 6, 2)),
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 1)),
        'organisateur': {
          'uid': 'org-2',
          'nom': 'Club B',
          'email': 'clubb@example.com',
          'role': 'club',
        },
        'participants': const [],
        'statut': 'archive',
        'lieu': 'Paris',
        'estPublic': false,
      });

      final map = event.toMap();
      expect(map['statut'], 'archive');
    });

    test('supports legacy aliases for organiser and dates', () {
      final event = Event.fromMap(
        {
          'title': 'Event legacy',
          'details': 'Ancien format',
          'startDate': '2026-06-01T08:00:00.000Z',
          'endDate': 1775000000000,
          'dateCreation': '2026-05-01T12:00:00.000Z',
          'ownerUid': 'org-legacy',
          'ownerName': 'Legacy Org',
          'ownerRole': 'club',
          'inscrits': [
            {
              'uid': 'joueur-legacy',
              'nom': 'Legacy Player',
              'email': 'legacy@example.com',
              'role': 'joueur',
            },
          ],
          'status': 'closed',
          'location': 'Yamoussoukro',
          'public': false,
        },
        fallbackId: 'legacy-event',
      );

      expect(event.id, 'legacy-event');
      expect(event.titre, 'Event legacy');
      expect(event.description, 'Ancien format');
      expect(event.organisateur.uid, 'org-legacy');
      expect(event.participants.single.uid, 'joueur-legacy');
      expect(event.statut, 'ferme');
      expect(event.lieu, 'Yamoussoukro');
      expect(event.estPublic, isFalse);
    });

    test('toMap stores organiser and participants as minimal embedded users',
        () {
      final event = Event.fromMap(
        {
          'id': 'event-min',
          'titre': 'Camp detection',
          'description': 'Tests et evaluation',
          'dateDebut': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
          'dateFin': Timestamp.fromDate(DateTime.utc(2026, 6, 2)),
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 1)),
          'organisateur': {
            'uid': 'org-embedded',
            'nom': 'Org Embedded',
            'email': 'org-embedded@example.com',
            'role': 'club',
            'eventPublies': [
              {'id': 'nested-event'}
            ],
          },
          'participants': [
            {
              'uid': 'player-embedded',
              'nom': 'Player Embedded',
              'email': 'player-embedded@example.com',
              'role': 'joueur',
              'offrePubliees': [
                {'id': 'nested-offer'}
              ],
            },
          ],
          'statut': 'ouvert',
          'lieu': 'Abidjan',
          'estPublic': true,
        },
      );

      final map = event.toMap();
      final organisateur =
          Map<String, dynamic>.from(map['organisateur'] as Map);
      final participant = Map<String, dynamic>.from(
        (map['participants'] as List).single as Map,
      );

      expect(organisateur['uid'], 'org-embedded');
      expect(organisateur.containsKey('eventPublies'), isFalse);
      expect(participant['uid'], 'player-embedded');
      expect(participant.containsKey('offrePubliees'), isFalse);
    });
  });
}
