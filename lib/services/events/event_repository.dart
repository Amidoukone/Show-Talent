import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EventRepository {
  EventRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _eventsCollection =>
      _firestore.collection('events');

  String newEventId() => _eventsCollection.doc().id;

  Stream<List<Event>> watchEvents() {
    return _eventsCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = data['id'] ?? doc.id;
        return Event.fromMap(data);
      }).toList(growable: false);
    });
  }

  Future<void> createEvent(Event event) {
    return _eventsCollection.doc(event.id).set(event.toMap());
  }

  Future<void> updateEvent(Event event) {
    return _eventsCollection.doc(event.id).update(event.toMap());
  }

  Future<void> deleteEvent(String eventId) {
    return _eventsCollection.doc(eventId).delete();
  }

  Future<Event?> fetchEventById(String eventId) async {
    final doc = await _eventsCollection.doc(eventId).get();
    if (!doc.exists) {
      return null;
    }

    final data = doc.data();
    if (data == null) {
      return null;
    }

    data['id'] = data['id'] ?? doc.id;
    return Event.fromMap(data);
  }

  Future<void> updateEventStatus({
    required String eventId,
    required String status,
    bool updateArchivedAt = false,
  }) {
    return _eventsCollection.doc(eventId).update(<String, dynamic>{
      'statut': status,
      'lastUpdated': FieldValue.serverTimestamp(),
      if (updateArchivedAt) 'archivedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateParticipants({
    required String eventId,
    required List<AppUser> participants,
  }) {
    return _eventsCollection.doc(eventId).update(<String, dynamic>{
      'participants': participants.map((p) => p.toMap()).toList(),
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }
}
