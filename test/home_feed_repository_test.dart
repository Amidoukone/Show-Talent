import 'package:adfoot/services/home/home_feed_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomeFeedRepository', () {
    test('fetchReadyVideoById returns only playable ready videos', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = HomeFeedRepository(firestore: firestore);

      await firestore.collection('videos').doc('ready-video').set({
        'status': 'ready',
        'videoUrl': 'https://cdn.example.com/ready.mp4',
        'uid': 'player-1',
      });
      await firestore.collection('videos').doc('processing-video').set({
        'status': 'processing',
        'videoUrl': 'https://cdn.example.com/processing.mp4',
        'uid': 'player-1',
      });

      final readyVideo = await repository.fetchReadyVideoById('ready-video');
      final processingVideo =
          await repository.fetchReadyVideoById('processing-video');

      expect(readyVideo?.id, 'ready-video');
      expect(processingVideo, isNull);
    });

    test('fetchSearchablePlayers hydrates player profiles with doc ids',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repository = HomeFeedRepository(firestore: firestore);

      await firestore.collection('users').doc('player-1').set({
        'nom': 'Awa Traore',
        'email': 'awa@example.com',
        'role': 'joueur',
        'photoProfil': '',
        'estActif': true,
        'emailVerified': true,
      });
      await firestore.collection('users').doc('club-1').set({
        'nom': 'Club Adfoot',
        'email': 'club@example.com',
        'role': 'club',
        'photoProfil': '',
        'estActif': true,
        'emailVerified': true,
      });

      final players = await repository.fetchSearchablePlayers();

      expect(players, hasLength(1));
      expect(players.single.uid, 'player-1');
      expect(players.single.isPlayer, isTrue);
    });

    test('fetchReadyVideosForAuthors keeps only playable ready videos',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repository = HomeFeedRepository(firestore: firestore);

      await firestore.collection('videos').doc('ready-player-1').set({
        'status': 'ready',
        'videoUrl': 'https://cdn.example.com/player-1.mp4',
        'uid': 'player-1',
      });
      await firestore.collection('videos').doc('ready-player-2').set({
        'status': 'ready',
        'videoUrl': 'https://cdn.example.com/player-2.mp4',
        'uid': 'player-2',
      });
      await firestore.collection('videos').doc('draft-player-1').set({
        'status': 'draft',
        'videoUrl': 'https://cdn.example.com/draft.mp4',
        'uid': 'player-1',
      });

      final videos = await repository.fetchReadyVideosForAuthors(
        const ['player-1'],
        limit: 20,
      );

      expect(videos.map((video) => video.id), ['ready-player-1']);
    });

    test('fetchRecentReadyVideos orders recent playable videos', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = HomeFeedRepository(firestore: firestore);

      await firestore.collection('videos').doc('older').set({
        'status': 'ready',
        'videoUrl': 'https://cdn.example.com/older.mp4',
        'uid': 'player-1',
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await firestore.collection('videos').doc('newer').set({
        'status': 'ready',
        'videoUrl': 'https://cdn.example.com/newer.mp4',
        'uid': 'player-2',
        'updatedAt': Timestamp.fromDate(DateTime(2026, 2, 1)),
      });
      await firestore.collection('videos').doc('empty-url').set({
        'status': 'ready',
        'videoUrl': '',
        'uid': 'player-3',
        'updatedAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
      });

      final videos = await repository.fetchRecentReadyVideos(limit: 20);

      expect(videos.map((video) => video.id), ['newer', 'older']);
    });
  });
}
