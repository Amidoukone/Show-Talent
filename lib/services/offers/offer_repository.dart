
import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/models/offre.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OfferRepositoryException implements Exception {
  const OfferRepositoryException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;
}

class OfferFeedCursor {
  const OfferFeedCursor._(this.snapshot);

  final DocumentSnapshot<Map<String, dynamic>> snapshot;
}

class OfferFeedPage {
  const OfferFeedPage({
    required this.offers,
    required this.cursor,
    required this.fetchedCount,
  });

  final List<Offre> offers;
  final OfferFeedCursor? cursor;
  final int fetchedCount;
}

class OfferLiveBatch {
  const OfferLiveBatch({
    required this.offers,
    required this.cursor,
    required this.fetchedCount,
  });

  final List<Offre> offers;
  final OfferFeedCursor? cursor;
  final int fetchedCount;
}

class OfferQueryFilter {
  const OfferQueryFilter({
    this.status,
    this.endingAfter,
    this.positions = const <FootballPosition>[],
  });

  final String? status;
  final DateTime? endingAfter;

  /// Postes recherches. Vide signifie « tous ».
  ///
  /// Le seul critere footballistique servi par le serveur, et c'est une
  /// contrainte de Firestore, pas un choix de produit : un index composite
  /// n'accepte **qu'un seul champ tableau**, et `ageCategories` en est un
  /// second. `TalentSearchRepository` tranche deja de la meme facon, dans
  /// l'autre sens du rapprochement -- le poste au serveur, le reste sur la
  /// page deja bornee.
  ///
  /// Le poste est aussi le bon choix des deux : c'est le critere le plus
  /// selectif, et celui qu'un joueur pose en premier.
  final List<FootballPosition> positions;

  /// Les codes envoyes a Firestore, plafonnes par `array-contains-any`.
  List<String> get positionCodesForQuery => positions
      .take(FootballPosition.maxPerQuery)
      .map((position) => position.code)
      .toList();

  String get cacheKey {
    final normalizedStatus =
        status == null ? 'all' : Offre.normalizeStatus(status!).trim();
    final dateKey = endingAfter?.millisecondsSinceEpoch.toString() ?? 'all';
    // Trie, sinon deux selections identiques faites dans un ordre different
    // relanceraient le flux pour rien.
    final positionKey = positions.isEmpty
        ? 'all'
        : (positions.map((position) => position.code).toList()..sort()).join(
            ',',
          );
    return '$normalizedStatus:$dateKey:$positionKey';
  }
}

class OfferRepository {
  static const int defaultPageSize = 40;

  OfferRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _offersCollection =>
      _firestore.collection('offres');

  Stream<OfferLiveBatch> watchOffers({
    int limit = defaultPageSize,
    OfferQueryFilter filter = const OfferQueryFilter(),
  }) {
    return _buildQuery(filter).limit(limit).snapshots().map((snapshot) {
      return OfferLiveBatch(
        offers: _parseSnapshotDocs(snapshot.docs),
        cursor: snapshot.docs.isEmpty
            ? null
            : OfferFeedCursor._(snapshot.docs.last),
        fetchedCount: snapshot.docs.length,
      );
    });
  }

  Future<OfferFeedPage> fetchOffersPage({
    int limit = defaultPageSize,
    OfferFeedCursor? startAfter,
    OfferQueryFilter filter = const OfferQueryFilter(),
  }) async {
    Query<Map<String, dynamic>> query = _buildQuery(filter).limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter.snapshot);
    }

    final snapshot = await query.get();
    return OfferFeedPage(
      offers: _parseSnapshotDocs(snapshot.docs),
      cursor: snapshot.docs.isEmpty
          ? startAfter
          : OfferFeedCursor._(snapshot.docs.last),
      fetchedCount: snapshot.docs.length,
    );
  }

  Future<void> incrementViews({
    required Offre offer,
    required AppUser viewer,
  }) async {
    if (viewer.uid == offer.recruteur.uid) return;

    final docRef = _offersCollection.doc(offer.id);

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      final data = snap.data();
      if (data == null) return;

      final rawRecruiter = data['recruteur'];
      final recruiterMap =
          rawRecruiter is Map ? Map<String, dynamic>.from(rawRecruiter) : null;
      final recruiterId = recruiterMap?['uid']?.toString();

      final viewedByRaw = data['viewedBy'];
      final viewedBy = viewedByRaw is List
          ? viewedByRaw.map((entry) => entry.toString()).toList()
          : <String>[];

      if (viewer.uid == recruiterId || viewedBy.contains(viewer.uid)) {
        return;
      }

      txn.update(docRef, {
        'vues': FieldValue.increment(1),
        'viewedBy': FieldValue.arrayUnion([viewer.uid]),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> publishOffer(Offre offer) {
    final payload = _payloadForCreate(offer);
    return _offersCollection.doc(offer.id).set(payload);
  }

  Future<void> updateOffer(Offre offer) {
    final payload = _payloadForUpdate(offer);
    return _offersCollection.doc(offer.id).update(payload);
  }

  Future<void> updateStatus({
    required String offerId,
    required String status,
  }) {
    final normalized = Offre.normalizeStatus(status);
    return _offersCollection.doc(offerId).update({
      'statut': normalized,
      'lastUpdated': FieldValue.serverTimestamp(),
      if (normalized == 'archivee')
        'archivedAt': FieldValue.serverTimestamp()
      else
        'archivedAt': FieldValue.delete(),
    });
  }

  Future<void> deleteOffer(String offerId) {
    return _offersCollection.doc(offerId).delete();
  }

  Future<void> applyToOffer({
    required AppUser player,
    required Offre offer,
  }) {
    final docRef = _offersCollection.doc(offer.id);

    return _firestore.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      if (!snap.exists) {
        throw const OfferRepositoryException(
          code: 'not-found',
          message: 'Offre introuvable.',
        );
      }

      final data = snap.data() ?? <String, dynamic>{};
      final status = Offre.normalizeStatus(
        data['statut']?.toString() ?? offer.statut,
      );
      if (!_isOpenStatus(status)) {
        throw const OfferRepositoryException(
          code: 'offer_closed',
          message: 'Vous ne pouvez pas postuler \u00e0 cette offre.',
        );
      }

      final candidates = _extractCandidateMaps(data['candidats']);
      final alreadyApplied = candidates
          .any((candidate) => candidate['uid']?.toString() == player.uid);
      if (alreadyApplied) {
        throw const OfferRepositoryException(
          code: 'already_applied',
          message: 'Vous avez d\u00e9j\u00e0 postul\u00e9 \u00e0 cette offre.',
        );
      }

      candidates.add(player.toEmbeddedMap());

      txn.update(docRef, {
        'candidats': candidates,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> withdrawFromOffer({
    required AppUser player,
    required Offre offer,
  }) {
    final docRef = _offersCollection.doc(offer.id);

    return _firestore.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      if (!snap.exists) {
        throw const OfferRepositoryException(
          code: 'not-found',
          message: 'Offre introuvable.',
        );
      }

      final data = snap.data() ?? <String, dynamic>{};
      final candidates = _extractCandidateMaps(data['candidats']);
      final isCandidate = candidates
          .any((candidate) => candidate['uid']?.toString() == player.uid);

      if (!isCandidate) {
        throw const OfferRepositoryException(
          code: 'not_applied',
          message: 'Vous n\u2019\u00eates pas inscrit \u00e0 cette offre.',
        );
      }

      final remainingCandidates = candidates
          .where((candidate) => candidate['uid']?.toString() != player.uid)
          .toList();

      txn.update(docRef, {
        'candidats': remainingCandidates,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  Map<String, dynamic> _payloadForCreate(Offre offer) {
    final payload = offer.toMap();
    payload['statut'] = Offre.normalizeStatus(offer.statut);
    payload['lastUpdated'] = FieldValue.serverTimestamp();
    if (offer.pieceJointeUrl == null) {
      payload.remove('pieceJointeUrl');
    }
    return payload;
  }

  /// Les champs qu'une mise a jour ne doit jamais reecrire.
  ///
  /// Ils appartiennent au serveur : `candidats` bouge par `applyToOffer` et
  /// `withdrawFromOffer`, `vues` et `viewedBy` par `incrementViews`, tous trois
  /// en transaction et sous une regle qui verifie le mouvement exact.
  /// Aucun formulaire ne les edite.
  ///
  /// Les envoyer quand meme etait une perte de donnees silencieuse. Le
  /// formulaire capture son offre une seule fois -- `editingOffre` est lu dans
  /// `initState` et fige jusqu'a l'enregistrement -- donc tout ce qui arrive
  /// pendant que l'ecran est ouvert etait ecrase par un etat perime : une
  /// candidature confirmee au joueur que le recruteur ne verrait jamais, un
  /// compteur de vues remis a sa valeur d'il y a dix minutes. Rien ne levait,
  /// parce que rien n'est illegal : la regle laisse le proprietaire ecrire ce
  /// qu'il veut sur sa propre offre.
  ///
  /// `update()` ne touche pas a ce qu'on ne lui envoie pas, donc les retirer
  /// suffit -- et c'est le depot qui les retire, pas l'ecran, pour que la
  /// garantie tienne quel que soit l'appelant.
  static const List<String> _serverOwnedOfferFields = <String>[
    'candidats',
    'vues',
    'viewedBy',
  ];

  Map<String, dynamic> _payloadForUpdate(Offre offer) {
    final payload = offer.toMap();
    payload['statut'] = Offre.normalizeStatus(offer.statut);
    payload['lastUpdated'] = FieldValue.serverTimestamp();
    if (offer.pieceJointeUrl == null) {
      payload['pieceJointeUrl'] = FieldValue.delete();
    }
    for (final field in _serverOwnedOfferFields) {
      payload.remove(field);
    }
    return payload;
  }

  List<Offre> _parseSnapshotDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    final fetched = <Offre>[];

    for (final doc in docs) {
      try {
        final offer = Offre.fromDoc(doc);
        final normalizedStatus = Offre.normalizeStatus(offer.statut);
        if (offer.statut != normalizedStatus) {
          offer.statut = normalizedStatus;
        }

        if (offer.dateFin.isBefore(now) && _isOpenStatus(offer.statut)) {
          _closeExpiredOffer(doc);
          offer.statut = 'fermee';
          offer.lastUpdated = now;
        }

        fetched.add(offer);
      } catch (error, stackTrace) {
        // This offer is now missing from the list, and nothing anywhere says
        // so: the publisher sees their offer absent and the players never see
        // it at all. `developer.log` reaches an attached debugger and nowhere
        // else, so on a real device a document that stopped parsing simply
        // erased an offer.
        //
        // `warning` rather than `error` because the snapshot re-delivers on
        // every change: sampling at 15% gives the rate without the flood.
        AppLogger.warning(
          'offer dropped from the list; its document did not parse',
          source: 'offers/parse',
          error: error,
          stackTrace: stackTrace,
          metadata: <String, dynamic>{'offerId': doc.id},
        );
      }
    }

    fetched.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
    return fetched;
  }

  void _closeExpiredOffer(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    doc.reference.update({
      'statut': 'fermee',
      'lastUpdated': FieldValue.serverTimestamp(),
    }).catchError((Object error, StackTrace stackTrace) {
      // The offer stays "ouverte" in Firestore past its end date, so players
      // keep being invited to apply to something that has closed. Retried
      // implicitly on the next snapshot, hence `warning` rather than `error`.
      AppLogger.warning(
        'expired offer could not be closed; it still reads as open',
        source: 'offers/auto_close',
        error: error,
        stackTrace: stackTrace,
      );
    });
  }

  /// Construit la requete du fil.
  ///
  /// Un seul index composite couvre le filtre par poste :
  /// `positionCodes CONTAINS` + `dateCreation DESC`. Le combiner avec `status`
  /// ou `endingAfter` produirait d'autres formes, chacune demandant son propre
  /// index -- et une forme sans index ne leve pas : Firestore repond
  /// `failed-precondition`, le depot l'attrape comme n'importe quel echec, et
  /// l'ecran parait simplement vide. C'est pourquoi l'appelant ne combine pas
  /// : le statut se filtre sur la page, comme le role et l'echeance le font
  /// deja.
  Query<Map<String, dynamic>> _buildQuery(OfferQueryFilter filter) {
    Query<Map<String, dynamic>> query = _offersCollection;

    if (filter.positions.isNotEmpty) {
      query = query.where(
        'positionCodes',
        arrayContainsAny: filter.positionCodesForQuery,
      );
    }

    final rawStatus = filter.status?.trim();
    if (rawStatus != null && rawStatus.isNotEmpty) {
      query = query.where(
        'statut',
        isEqualTo: Offre.normalizeStatus(rawStatus),
      );
    }

    if (filter.endingAfter != null) {
      query = query.where(
        'dateFin',
        isGreaterThanOrEqualTo: Timestamp.fromDate(filter.endingAfter!),
      );
      query =
          query.orderBy('dateFin').orderBy('dateCreation', descending: true);
    } else {
      query = query.orderBy('dateCreation', descending: true);
    }

    return query;
  }

  static bool _isOpenStatus(String status) {
    return Offre.normalizeStatus(status) == 'ouverte';
  }

  static List<Map<String, dynamic>> _extractCandidateMaps(dynamic raw) {
    if (raw is! List) {
      return <Map<String, dynamic>>[];
    }

    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }
}
