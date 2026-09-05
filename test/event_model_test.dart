import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/models/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Event model parsing', () {
    test('uses fallback id and parses mixed date formats safely', () {
      final event = Event.fromMap(
        {
          'titre': 'Détection régionale',
          'description': 'Journée de tests joueurs.',
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
      expect(event.titre, 'Détection régionale');
      expect(event.description, 'Journée de tests joueurs.');
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

  // Le vocabulaire footballistique arrive sur l'evenement, avec les memes
  // regles que sur l'offre : le code est stocke, le libelle est affiche, et un
  // code inconnu est ignore plutot que de faire echouer la fiche entiere.
  group('Event vocabulaire footballistique', () {
    AppUser organiser() => AppUser.fromEmbeddedMap(const {
          'uid': 'club-1',
          'nom': 'Club A',
          'email': 'club@example.com',
          'role': 'club',
        });

    Map<String, dynamic> rawEvent(Map<String, dynamic> extra) => {
          'titre': 'Detection',
          'description': 'desc',
          'organisateur': const {
            'uid': 'club-1',
            'nom': 'Club A',
            'email': 'club@example.com',
            'role': 'club',
          },
          'participants': const <Map<String, dynamic>>[],
          'statut': 'ouvert',
          'lieu': 'Abidjan',
          'estPublic': true,
          ...extra,
        };

    Event build({
      List<FootballPosition> positions = const <FootballPosition>[],
      List<AgeCategory> categories = const <AgeCategory>[],
      ClubLevel? level,
    }) {
      return Event(
        id: 'event-1',
        titre: 'Detection U19',
        description: 'Tests techniques.',
        dateDebut: DateTime.utc(2026, 7, 1),
        dateFin: DateTime.utc(2026, 7, 2),
        organisateur: organiser(),
        participants: const [],
        statut: 'ouvert',
        lieu: 'Abidjan',
        estPublic: true,
        createdAt: DateTime.utc(2026, 6, 1),
        positionCodes: positions,
        ageCategories: categories,
        clubLevel: level,
      );
    }

    test('les codes font l aller-retour', () {
      final map = build(
        positions: const [
          FootballPosition.leftBack,
          FootballPosition.centreBack,
        ],
        categories: const [AgeCategory.u19],
        level: ClubLevel.academy,
      ).toMap();

      expect(map['positionCodes'], ['LB', 'CB']);
      expect(map['ageCategories'], ['U19']);
      expect(map['clubLevel'], 'academy');

      final parsed = Event.fromMap(Map<String, dynamic>.from(map));
      expect(parsed.positionCodes, [
        FootballPosition.leftBack,
        FootballPosition.centreBack,
      ]);
      expect(parsed.ageCategories, [AgeCategory.u19]);
      expect(parsed.clubLevel, ClubLevel.academy);
    });

    test('un decochage part au lieu d etre omis', () {
      // Ecrits sans condition, contrairement aux autres champs optionnels : une
      // charge utile qui omettrait la cle laisserait `update()` garder
      // l'ancienne valeur, et l'evenement resterait affiche dans une recherche
      // par poste qu'il ne vise plus. Meme defaut que celui corrige sur `tags`.
      final map = build().toMap();

      expect(map.containsKey('positionCodes'), isTrue);
      expect(map['positionCodes'], isEmpty);
      expect(map.containsKey('ageCategories'), isTrue);
      expect(map['ageCategories'], isEmpty);
      expect(map.containsKey('clubLevel'), isTrue);
      expect(map['clubLevel'], isNull);
    });

    test('un code inconnu est ignore, pas fatal', () {
      final parsed = Event.fromMap(rawEvent({
        'positionCodes': const ['LB', 'LIBERO', 'LB'],
        'ageCategories': const ['U19', 'U99'],
        'clubLevel': 'interplanetaire',
      }));

      expect(parsed.positionCodes, [FootballPosition.leftBack]);
      expect(parsed.ageCategories, [AgeCategory.u19]);
      expect(parsed.clubLevel, isNull);
    });

    test('un document ancien, sans vocabulaire, reste lisible', () {
      final parsed = Event.fromMap(rawEvent(const {}));

      expect(parsed.positionCodes, isEmpty);
      expect(parsed.ageCategories, isEmpty);
      expect(parsed.clubLevel, isNull);
    });

    test('la borne est celle de la requete, pas celle du joueur', () {
      // Une detection cherche souvent plusieurs postes a la fois ; la borne
      // utile est celle d'`array-contains-any`, pas les trois postes que
      // declare une fiche de joueur.
      final codes = FootballPosition.values.map((p) => p.code).toList();
      expect(codes.length, FootballPosition.maxPerQuery);

      final parsed = Event.fromMap(rawEvent({'positionCodes': codes}));
      expect(parsed.positionCodes, hasLength(FootballPosition.maxPerQuery));
    });
  });
}
