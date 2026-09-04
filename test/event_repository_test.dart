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
  List<String>? tags,
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
    tags: tags,
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
      'watchEvents tolerates a mistyped optional field instead of dropping '
      'the document',
      () async {
        // Event.fromMap now falls back to safe defaults for mistyped
        // optional fields (see AppUser._fromMap hardening) instead of
        // throwing, so a document like this is no longer silently excluded
        // from the feed -- it used to vanish with no trace, which is worse
        // than showing it with a defaulted field.
        final firestore = FakeFirebaseFirestore();
        final repository = EventRepository(firestore: firestore);

        await repository.createEvent(_event(id: 'valid'));
        await firestore.collection('events').doc('quirky').set({
          'id': 'quirky',
          'titre': 'Event with an invalid public flag',
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

        expect(
          batch.events.map((event) => event.id).toSet(),
          {'valid', 'quirky'},
        );
        expect(
          batch.events.firstWhere((event) => event.id == 'quirky').estPublic,
          isTrue,
        );
        expect(batch.fetchedCount, 2);
        expect(batch.cursor, isNotNull);
      },
    );

    // La regle `canMutateEventViews` epingle exactement trois champs et un
    // delta de un. Ces trois cas sont ce qu'elle accepte, du cote client.
    group('incrementViews', () {
      test('counts a reader once, and touches only what the rule allows',
          () async {
        final firestore = FakeFirebaseFirestore();
        final repository = EventRepository(firestore: firestore);
        final player = _user('player-1', 'joueur');

        await repository.createEvent(_event());
        await repository.incrementViews(event: _event(), viewer: player);
        await repository.incrementViews(event: _event(), viewer: player);

        final data = (await firestore.collection('events').doc('event-1').get())
            .data()!;

        expect(data['views'], 1, reason: 'le second passage ne recompte pas');
        expect(data['viewedBy'], ['player-1']);
        expect(data['lastUpdated'], isA<Timestamp>());
        expect(data['statut'], 'ouvert');
        expect(data['titre'], 'Camp detection');
      });

      test('never counts the organiser in their own event', () async {
        final firestore = FakeFirebaseFirestore();
        final repository = EventRepository(firestore: firestore);
        final organizer = _user('club-1', 'club');

        await repository.createEvent(_event(organizer: organizer));
        await repository.incrementViews(event: _event(), viewer: organizer);

        final data = (await firestore.collection('events').doc('event-1').get())
            .data()!;

        expect(data['views'], isNull);
        expect(data['viewedBy'], isNull);
      });

      test('two readers count twice', () async {
        final firestore = FakeFirebaseFirestore();
        final repository = EventRepository(firestore: firestore);

        await repository.createEvent(_event());
        await repository.incrementViews(
          event: _event(),
          viewer: _user('player-1', 'joueur'),
        );
        await repository.incrementViews(
          event: _event(),
          viewer: _user('player-2', 'joueur'),
        );

        final data = (await firestore.collection('events').doc('event-1').get())
            .data()!;

        expect(data['views'], 2);
        expect(data['viewedBy'], ['player-1', 'player-2']);
      });
    });

    group('updateEvent clears what the form emptied', () {
      // `toMap` n'ecrit ses champs optionnels que s'ils sont non nuls, donc un
      // champ vide sortait de la charge utile et `update()` gardait l'ancienne
      // valeur. L'organisateur voyait les tags disparaitre de l'ecran -- l'etat
      // local est remplace apres succes -- et les retrouvait au rechargement.
      test('emptied tags and capacity reach Firestore', () async {
        final firestore = FakeFirebaseFirestore();
        final repository = EventRepository(firestore: firestore);

        await repository.createEvent(
          _event(capacity: 30, tags: const ['u19', 'detection']),
        );
        await repository.updateEvent(_event());

        final data = (await firestore.collection('events').doc('event-1').get())
            .data()!;

        expect(data.containsKey('tags'), isFalse);
        expect(data.containsKey('capaciteMax'), isFalse);
      });

      test('tags and capacity still round-trip when they are set', () async {
        final firestore = FakeFirebaseFirestore();
        final repository = EventRepository(firestore: firestore);

        await repository.createEvent(_event());
        await repository.updateEvent(
          _event(capacity: 24, tags: const ['u17']),
        );

        final data = (await firestore.collection('events').doc('event-1').get())
            .data()!;

        expect(data['tags'], ['u17']);
        expect(data['capaciteMax'], 24);
      });
    });
  });
}
