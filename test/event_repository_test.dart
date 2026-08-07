import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/events/event_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _user(String uid, String role) {
  return AppUser(
    uid: uid,
    nom: 'User $uid',
    email: '$uid@example.com',
    role: role,
    photoProfil: '',
    estActif: true,
    emailVerified: true,
    followers: 0,
    followings: 0,
    dateInscription: DateTime(2026, 1, 1),
    dernierLogin: DateTime(2026, 1, 1),
    followersList: const [],
    followingsList: const [],
  );
}

Event _event({
  String id = 'event-1',
  String status = 'ouvert',
  AppUser? organizer,
  List<AppUser> participants = const [],
  int? capacity,
}) {
  return Event(
    id: id,
    titre: 'Camp detection',
    description: 'Tests techniques et evaluation joueurs.',
    dateDebut: DateTime(2026, 7, 1),
    dateFin: DateTime(2026, 7, 2),
    organisateur: organizer ?? _user('club-1', 'club'),
    participants: participants,
    statut: status,
    lieu: 'Abidjan',
    estPublic: true,
    createdAt: DateTime(2026, 6, 1),
    capaciteMax: capacity,
  );
}

void main() {
  group('EventRepository', () {
    test(
      'registerParticipant updates only participants and lastUpdated data',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = EventRepository(firestore: firestore);
        final player = _user('player-1', 'joueur');

        await repository.createEvent(_event(capacity: 2));
        await repository.registerParticipant(
          eventId: 'event-1',
          participant: player,
        );

        final data = (await firestore.collection('events').doc('event-1').get())
            .data()!;
        final participants = List<Map<String, dynamic>>.from(
          (data['participants'] as List).map(
            (entry) => Map<String, dynamic>.from(entry as Map),
          ),
        );

        expect(participants.map((entry) => entry['uid']), ['player-1']);
        expect(data['statut'], 'ouvert');
        expect(data['lastUpdated'], isA<Timestamp>());
      },
    );

    test('registerParticipant rejects duplicates and full events', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = EventRepository(firestore: firestore);
      final player = _user('player-1', 'joueur');

      await repository.createEvent(_event(capacity: 1));
      await repository.registerParticipant(
        eventId: 'event-1',
        participant: player,
      );

      expect(
        () => repository.registerParticipant(
          eventId: 'event-1',
          participant: player,
        ),
        throwsA(
          isA<EventRepositoryException>().having(
            (error) => error.code,
            'code',
            'already_registered',
          ),
        ),
      );

      expect(
        () => repository.registerParticipant(
          eventId: 'event-1',
          participant: _user('player-2', 'joueur'),
        ),
        throwsA(
          isA<EventRepositoryException>().having(
            (error) => error.code,
            'code',
            'capacity_reached',
          ),
        ),
      );
    });

    test(
      'watchEvents skips malformed documents instead of failing the stream',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = EventRepository(firestore: firestore);

        await repository.createEvent(_event(id: 'valid'));
        await firestore.collection('events').doc('malformed').set({
          'id': 'malformed',
          'titre': 'Bad event',
          'description': 'Payload with an invalid public flag.',
          'dateDebut': Timestamp.fromDate(DateTime(2026, 7, 1)),
          'dateFin': Timestamp.fromDate(DateTime(2026, 7, 2)),
          'createdAt': Timestamp.fromDate(DateTime(2026, 6, 2)),
          'organisateur': _user('club-2', 'club').toEmbeddedMap(),
          'participants': const <Map<String, dynamic>>[],
          'statut': 'ouvert',
          'lieu': 'Dakar',
          'estPublic': 'yes',
        });

        final batch = await repository.watchEvents(limit: 10).first;

        expect(batch.events.map((event) => event.id), ['valid']);
        expect(batch.fetchedCount, 2);
        expect(batch.cursor, isNotNull);
      },
    );
  });
}
