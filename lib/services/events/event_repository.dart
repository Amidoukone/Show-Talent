import 'dart:io';

import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class EventRepositoryException implements Exception {
  const EventRepositoryException({required this.code, required this.message});

  final String code;
  final String message;
}

class EventFeedCursor {
  const EventFeedCursor._(this.snapshot);

  final DocumentSnapshot<Map<String, dynamic>> snapshot;
}

class EventFeedPage {
  const EventFeedPage({
    required this.events,
    required this.cursor,
    required this.fetchedCount,
  });

  final List<Event> events;
  final EventFeedCursor? cursor;
  final int fetchedCount;
}

class EventLiveBatch {
  const EventLiveBatch({
    required this.events,
    required this.cursor,
    required this.fetchedCount,
  });

  final List<Event> events;
  final EventFeedCursor? cursor;
  final int fetchedCount;
}

class EventQueryFilter {
  const EventQueryFilter({this.status, this.endingAfter});

  final String? status;
  final DateTime? endingAfter;

  bool get hasDateFilter => endingAfter != null;

  String get cacheKey {
    final normalizedStatus = status == null
        ? 'all'
        : Event.normalizeStatus(status!).trim();
    final dateKey = endingAfter?.millisecondsSinceEpoch.toString() ?? 'all';
    return '$normalizedStatus:$dateKey';
  }
}

class EventRepository {
  static const int defaultPageSize = 40;

  EventRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _injectedStorage = storage;

  final FirebaseFirestore _firestore;

  // Resolu a l'usage : `FirebaseStorage.instance` lance quand aucune app
  // Firebase n'est demarree, et les tests construisent ce depot avec un
  // Firestore factice sans jamais toucher au stockage.
  final FirebaseStorage? _injectedStorage;

  FirebaseStorage get _storage => _injectedStorage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _eventsCollection =>
      _firestore.collection('events');

  String newEventId() => _eventsCollection.doc().id;

  Stream<EventLiveBatch> watchEvents({
    int limit = defaultPageSize,
    EventQueryFilter filter = const EventQueryFilter(),
  }) {
    return _buildQuery(filter).limit(limit).snapshots().map((snapshot) {
      return EventLiveBatch(
        events: _eventsFromDocs(snapshot.docs),
        cursor: snapshot.docs.isEmpty
            ? null
            : EventFeedCursor._(snapshot.docs.last),
        fetchedCount: snapshot.docs.length,
      );
    });
  }

  Future<EventFeedPage> fetchEventsPage({
    int limit = defaultPageSize,
    EventFeedCursor? startAfter,
    EventQueryFilter filter = const EventQueryFilter(),
  }) async {
    Query<Map<String, dynamic>> query = _buildQuery(filter).limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter.snapshot);
    }

    final snapshot = await query.get();
    return EventFeedPage(
      events: _eventsFromDocs(snapshot.docs),
      cursor: snapshot.docs.isEmpty
          ? startAfter
          : EventFeedCursor._(snapshot.docs.last),
      fetchedCount: snapshot.docs.length,
    );
  }

  Future<void> createEvent(Event event) {
    final payload = event.toMap();
    payload['statut'] = Event.normalizeStatus(event.statut);
    payload['lastUpdated'] = FieldValue.serverTimestamp();
    return _eventsCollection.doc(event.id).set(payload);
  }

  /// Compte un lecteur, une fois.
  ///
  /// Transpose mot pour mot ce que fait `OfferRepository.incrementViews`, y
  /// compris sa semantique : l'appelant compte une impression dans la liste,
  /// pas une ouverture de fiche. Les deux nombres doivent vouloir dire la
  /// meme chose, sans quoi comparer une offre et un evenement ne veut rien
  /// dire.
  ///
  /// L'organisateur ne compte pas dans son propre evenement, et la liste
  /// `viewedBy` fait office de dedoublonnage -- relue dans la transaction
  /// plutot que depuis l'objet recu, qui peut dater.
  Future<void> incrementViews({
    required Event event,
    required AppUser viewer,
  }) async {
    if (viewer.uid == event.organisateur.uid) return;

    final docRef = _eventsCollection.doc(event.id);

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      final data = snap.data();
      if (data == null) return;

      final rawOrganiser = data['organisateur'];
      final organiserMap =
          rawOrganiser is Map ? Map<String, dynamic>.from(rawOrganiser) : null;
      final organiserId = organiserMap?['uid']?.toString();

      final viewedByRaw = data['viewedBy'];
      final viewedBy = viewedByRaw is List
          ? viewedByRaw.map((entry) => entry.toString()).toList()
          : <String>[];

      if (viewer.uid == organiserId || viewedBy.contains(viewer.uid)) {
        return;
      }

      txn.update(docRef, {
        'views': FieldValue.increment(1),
        'viewedBy': FieldValue.arrayUnion([viewer.uid]),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
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
    if (event.streamingUrl == null) {
      payload['streamingUrl'] = FieldValue.delete();
    }
    if (event.flyerUrl == null) {
      payload['flyerUrl'] = FieldValue.delete();
    }
    return _eventsCollection.doc(event.id).update(payload);
  }

  /// Televerse l'affiche d'un evenement et renvoie son URL.
  ///
  /// Appelable seulement une fois le document cree : `isOwnedEventDoc` le lit
  /// pour verifier qui televerse, et un document absent fait echouer la regle.
  /// C'est aussi ce qui donne au fichier un nom stable -- l'identifiant de
  /// l'evenement -- donc remplacer une affiche ecrase l'ancienne au lieu
  /// d'accumuler des orphelines.
  Future<String> uploadFlyer({
    required String eventId,
    required String filePath,
  }) async {
    final ref = _storage.ref('eventFlyers/$eventId');
    await ref.putFile(
      File(filePath),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
  }

  /// Ecrit l'URL de l'affiche, et rien d'autre.
  Future<void> setFlyerUrl({
    required String eventId,
    required String? flyerUrl,
  }) {
    return _eventsCollection.doc(eventId).update({
      'flyerUrl': flyerUrl ?? FieldValue.delete(),
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  /// Supprime l'affiche du stockage, sans faire echouer l'appelant.
  ///
  /// Un fichier absent est le cas courant -- la plupart des evenements n'ont
  /// pas d'affiche -- et ce n'est pas une erreur.
  Future<void> deleteFlyer(String eventId) async {
    try {
      await _storage.ref('eventFlyers/$eventId').delete();
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') return;
      AppLogger.warning(
        'Suppression affiche evenement echouee: $error',
        source: 'EventRepository.deleteFlyer',
        error: error,
      );
    }
  }

  /// Supprime l'evenement, puis son affiche.
  ///
  /// Dans cet ordre : la regle de stockage lit le document pour autoriser la
  /// suppression du fichier, donc l'inverse marcherait par accident tant que
  /// le document existe encore, et pas apres. L'affiche est donc retiree
  /// avant, et le document ensuite.
  Future<void> deleteEvent(String eventId) async {
    await deleteFlyer(eventId);
    await _eventsCollection.doc(eventId).delete();
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
          message: 'L’événement n’existe pas.',
        );
      }

      final event = Event.fromDoc(snap);
      final status = Event.normalizeStatus(event.statut);
      if (status == 'ferme' || status == 'archive') {
        throw const EventRepositoryException(
          code: 'event_closed',
          message: 'L’événement n’est pas ouvert.',
        );
      }

      final alreadyRegistered = event.participants.any(
        (p) => p.uid == participant.uid,
      );
      if (alreadyRegistered) {
        throw const EventRepositoryException(
          code: 'already_registered',
          message: 'Vous êtes déjà inscrit à cet événement.',
        );
      }

      if (event.capaciteMax != null &&
          event.participants.length >= event.capaciteMax!) {
        throw const EventRepositoryException(
          code: 'capacity_reached',
          message: 'La capacité maximale de cet événement est atteinte.',
        );
      }

      // The stored maps are carried over verbatim, never re-serialised
      // through AppUser. Two reasons, and the second is the one that bites:
      //
      // - a round trip through the model rewrites every *other* participant's
      //   embedded copy on each registration, so one person joining can
      //   silently change what is recorded about everybody already in;
      // - the Firestore rule now requires the new list to contain the old one
      //   unchanged (`hasAll`), which is what stops a participant from
      //   removing rivals. A lossy round trip — a legacy entry missing a field
      //   the model defaults, a null the model drops — produces maps that no
      //   longer compare equal, and the rule would reject a perfectly
      //   legitimate registration.
      //
      // This mirrors what OfferRepository already does with `candidats`.
      final participants = <Map<String, dynamic>>[
        ..._extractParticipantMaps(snap.data()?['participants']),
        participant.toEmbeddedMap(),
      ];

      txn.update(docRef, {
        'participants': participants,
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
          message: 'L’événement n’existe pas.',
        );
      }

      final event = Event.fromDoc(snap);
      final status = Event.normalizeStatus(event.statut);
      if (status == 'ferme' || status == 'archive') {
        throw const EventRepositoryException(
          code: 'event_closed',
          message: 'L’événement n’est plus ouvert.',
        );
      }

      final isRegistered = event.participants.any(
        (p) => p.uid == participant.uid,
      );
      if (!isRegistered) {
        throw const EventRepositoryException(
          code: 'not_registered',
          message: 'Vous n’êtes pas inscrit à cet événement.',
        );
      }

      // Verbatim again, for the reasons on registerParticipant: the withdrawal
      // rule requires the old list to contain the new one unchanged, so the
      // entries that stay must be exactly the bytes that were stored.
      final participants = _extractParticipantMaps(snap.data()?['participants'])
          .where((entry) => entry['uid']?.toString() != participant.uid)
          .toList(growable: false);

      txn.update(docRef, {
        'participants': participants,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  /// The stored participant maps, exactly as Firestore holds them.
  ///
  /// Mirrors `OfferRepository._extractCandidateMaps`. Reading them straight
  /// off the snapshot instead of through [Event] is what keeps a write
  /// byte-identical for every participant this call is not adding or removing.
  static List<Map<String, dynamic>> _extractParticipantMaps(dynamic raw) {
    if (raw is! List) {
      return <Map<String, dynamic>>[];
    }

    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Query<Map<String, dynamic>> _buildQuery(EventQueryFilter filter) {
    Query<Map<String, dynamic>> query = _eventsCollection;

    final rawStatus = filter.status?.trim();
    if (rawStatus != null && rawStatus.isNotEmpty) {
      query = query.where(
        'statut',
        isEqualTo: Event.normalizeStatus(rawStatus),
      );
    }

    if (filter.endingAfter != null) {
      query = query.where(
        'dateFin',
        isGreaterThanOrEqualTo: Timestamp.fromDate(filter.endingAfter!),
      );
      query = query.orderBy('dateFin').orderBy('createdAt', descending: true);
    } else {
      query = query.orderBy('createdAt', descending: true);
    }

    return query;
  }

  static List<Event> _eventsFromDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final fetched = <Event>[];

    for (final doc in docs) {
      try {
        fetched.add(Event.fromDoc(doc));
      } catch (error, stackTrace) {
        // Meme defaut que pour une offre, et meme correction : l'evenement
        // disparait de l'onglet sans que rien ne le dise. L'organisateur voit
        // sa detection absente, les joueurs ne la voient jamais, et
        // `AppLogger.debug` s'arrete a `developer.log` -- donc a un debogueur
        // que personne n'a attache sur un vrai telephone.
        //
        // `warning` plutot que `error` parce que l'instantane se redelivre a
        // chaque changement : l'echantillonnage a 15 % donne le taux sans
        // noyer la collection si un document reste durablement casse.
        AppLogger.warning(
          'event dropped from the list; its document did not parse',
          source: 'events/parse',
          error: error,
          stackTrace: stackTrace,
          metadata: <String, dynamic>{'eventId': doc.id},
        );
      }
    }

    return fetched;
  }
}
