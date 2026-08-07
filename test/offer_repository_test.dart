import 'package:adfoot/models/offre.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/offers/offer_repository.dart';
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

Offre _offer({
  String id = 'offer-1',
  String status = 'ouverte',
  AppUser? recruiter,
  List<AppUser> candidates = const [],
  DateTime? endDate,
  String? attachmentUrl,
}) {
  return Offre(
    id: id,
    titre: 'Recherche milieu',
    description: 'Profil technique et disponible.',
    dateDebut: DateTime(2026, 1, 1),
    dateFin: endDate ?? DateTime(2026, 12, 31),
    recruteur: recruiter ?? _user('club-1', 'club'),
    candidats: candidates,
    statut: status,
    dateCreation: DateTime(2026, 1, 1),
    pieceJointeUrl: attachmentUrl,
  );
}

void main() {
  group('OfferRepository', () {
    test('publishOffer normalizes status and omits empty attachment', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = OfferRepository(firestore: firestore);

      await repository.publishOffer(_offer(status: 'ferm\u00e9e'));

      final data =
          (await firestore.collection('offres').doc('offer-1').get()).data()!;
      expect(data['statut'], 'fermee');
      expect(data.containsKey('pieceJointeUrl'), isFalse);
    });

    test('updateOffer removes attachment when cleared', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = OfferRepository(firestore: firestore);

      await repository.publishOffer(
        _offer(attachmentUrl: 'https://example.com/cv.pdf'),
      );
      await repository.updateOffer(_offer());

      final data =
          (await firestore.collection('offres').doc('offer-1').get()).data()!;
      expect(data.containsKey('pieceJointeUrl'), isFalse);
    });

    test('applyToOffer adds one candidate and rejects duplicates', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = OfferRepository(firestore: firestore);
      final player = _user('player-1', 'joueur');

      await repository.publishOffer(_offer());
      await repository.applyToOffer(player: player, offer: _offer());

      final data =
          (await firestore.collection('offres').doc('offer-1').get()).data()!;
      final candidates = List<Map<String, dynamic>>.from(
        (data['candidats'] as List).map(
          (entry) => Map<String, dynamic>.from(entry as Map),
        ),
      );
      expect(candidates.map((entry) => entry['uid']), ['player-1']);

      expect(
        () => repository.applyToOffer(player: player, offer: _offer()),
        throwsA(
          isA<OfferRepositoryException>()
              .having((error) => error.code, 'code', 'already_applied'),
        ),
      );
    });

    test('withdrawFromOffer removes an existing candidate', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = OfferRepository(firestore: firestore);
      final player = _user('player-1', 'joueur');

      await repository.publishOffer(_offer(candidates: [player]));
      await repository.withdrawFromOffer(player: player, offer: _offer());

      final data =
          (await firestore.collection('offres').doc('offer-1').get()).data()!;
      expect(data['candidats'], isEmpty);
    });

    test('incrementViews skips recruiter and deduplicates viewers', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = OfferRepository(firestore: firestore);
      final recruiter = _user('club-1', 'club');
      final viewer = _user('player-1', 'joueur');

      await repository.publishOffer(_offer(recruiter: recruiter));
      await repository.incrementViews(
          offer: _offer(recruiter: recruiter), viewer: recruiter);
      await repository.incrementViews(
          offer: _offer(recruiter: recruiter), viewer: viewer);
      await repository.incrementViews(
          offer: _offer(recruiter: recruiter), viewer: viewer);

      final data =
          (await firestore.collection('offres').doc('offer-1').get()).data()!;
      expect(data['vues'], 1);
      expect(data['viewedBy'], ['player-1']);
    });

    test('watchOffers emits sorted normalized offers', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = OfferRepository(firestore: firestore);

      await firestore.collection('offres').doc('older').set({
        ..._offer(id: 'older', status: 'archiv\u00e9e').toMap(),
        'dateCreation': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await firestore.collection('offres').doc('newer').set({
        ..._offer(id: 'newer', status: 'ouverte').toMap(),
        'dateCreation': Timestamp.fromDate(DateTime(2026, 2, 1)),
      });

      final offers = (await repository.watchOffers().first).offers;

      expect(offers.map((offer) => offer.id), ['newer', 'older']);
      expect(offers.last.statut, 'archivee');
    });

    test('watchOffers and fetchOffersPage use bounded ordered queries',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repository = OfferRepository(firestore: firestore);

      for (var index = 0; index < 3; index += 1) {
        final createdAt = DateTime(2026, 1, index + 1);
        await firestore.collection('offres').doc('offer-$index').set({
          ..._offer(id: 'offer-$index').toMap(),
          'dateCreation': Timestamp.fromDate(createdAt),
        });
      }

      final firstBatch = await repository.watchOffers(limit: 2).first;
      expect(
          firstBatch.offers.map((offer) => offer.id), ['offer-2', 'offer-1']);
      expect(firstBatch.fetchedCount, 2);
      expect(firstBatch.cursor, isNotNull);

      final fullPage = await repository.fetchOffersPage(limit: 20);
      expect(fullPage.offers.map((offer) => offer.id),
          ['offer-2', 'offer-1', 'offer-0']);
      expect(fullPage.fetchedCount, 3);
    });
  });
}
