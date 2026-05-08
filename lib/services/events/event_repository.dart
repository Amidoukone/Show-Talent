import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EventRepositoryException implements Exception {
  const EventRepositoryException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;
}

class EventRepository {
  EventRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _eventsCollection =>
      _firestore.collection('events');

  String newEventId() => _eventsCollection.doc().id;

  Stream<List<Event>> watchEvents() {
    return _eventsCollection.snapshots().map((snapshot) {
      return snapshot.docs.map(Event.fromDoc).toList(growable: false);
    });
  }

  Future<void> createEvent(Event event) {
    final payload = event.toMap();
    payload['statut'] = Event.normalizeStatus(event.statut);
    payload['lastUpdated'] = FieldValue.serverTimestamp();
    return _eventsCollection.doc(event.id).set(payload);
  }

  Future<void> updateEvent(Event event) {
    final payload = event.toMap();
    final status = Event.normalizeStatus(event.statut);
    payload['statut'] = status;
    payload['lastUpdated'] = FieldValue.serverTimestamp();
    if (status == 'archive') {
      payload['archivedAt'] = FieldValue.serverTimestamp();
    } else {
      payload['archivedAt'] = FieldValue.delete();
    }
    return _eventsCollection.doc(event.id).update(payload);
  }

  Future<void> deleteEvent(String eventId) {
    return _eventsCollection.doc(eventId).delete();
  }

  Future<Event?> fetchEventById(String eventId) async {
    final doc = await _eventsCollection.doc(eventId).get();
    if (!doc.exists) {
      return null;
    }

    return Event.fromDoc(doc);
  }

  Future<void> updateEventStatus({
    required String eventId,
    required String status,
  }) {
    final normalizedStatus = Event.normalizeStatus(status);
    return _eventsCollection.doc(eventId).update(<String, dynamic>{
      'statut': normalizedStatus,
      'lastUpdated': FieldValue.serverTimestamp(),
      if (normalizedStatus == 'archive')
        'archivedAt': FieldValue.serverTimestamp()
      else
        'archivedAt': FieldValue.delete(),
    });
  }

  Future<void> registerParticipant({
    required String eventId,
    required AppUser participant,
  }) {
    final docRef = _eventsCollection.doc(eventId);

    return _firestore.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      if (!snap.exists) {
        throw const EventRepositoryException(
          code: 'not-found',
          message: 'L\'evenement n\'existe pas.',
        );
      }

      final event = Event.fromDoc(snap);
      final status = Event.normalizeStatus(event.statut);
      if (status == 'ferme' || status == 'archive') {
        throw const EventRepositoryException(
          code: 'event_closed',
          message: 'L\'evenement n\'est pas ouvert.',
        );
      }

      final alreadyRegistered =
          event.participants.any((p) => p.uid == participant.uid);
      if (alreadyRegistered) {
        throw const EventRepositoryException(
          code: 'already_registered',
          message: 'Vous etes deja inscrit a cet evenement.',
        );
      }

      if (event.capaciteMax != null &&
          event.participants.length >= event.capaciteMax!) {
        throw const EventRepositoryException(
          code: 'capacity_reached',
          message: 'La capacite maximale de cet evenement est atteinte.',
        );
      }

      final participants = [
        ...event.participants.map((p) => p.toEmbeddedMap()),
        participant.toEmbeddedMap(),
      ];

      txn.update(docRef, {
        'participants': participants,
        'statut': status,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> unregisterParticipant({
    required String eventId,
    required AppUser participant,
  }) {
    final docRef = _eventsCollection.doc(eventId);

    return _firestore.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      if (!snap.exists) {
        throw const EventRepositoryException(
          code: 'not-found',
          message: 'L\'evenement n\'existe pas.',
        );
      }

      final event = Event.fromDoc(snap);
      final status = Event.normalizeStatus(event.statut);
      if (status == 'ferme' || status == 'archive') {
        throw const EventRepositoryException(
          code: 'event_closed',
          message: 'L\'evenement n\'est plus ouvert.',
        );
      }

      final isRegistered =
          event.participants.any((p) => p.uid == participant.uid);
      if (!isRegistered) {
        throw const EventRepositoryException(
          code: 'not_registered',
          message: 'Vous n\'etes pas inscrit a cet evenement.',
        );
      }

      final participants = event.participants
          .where((p) => p.uid != participant.uid)
          .map((p) => p.toEmbeddedMap())
          .toList(growable: false);

      txn.update(docRef, {
        'participants': participants,
        'statut': status,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }
}
