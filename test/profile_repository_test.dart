import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/users/profile_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProfileRepository', () {
    test(
        'fetchUser returns null for missing profiles and parses existing users',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repository = ProfileRepository(firestore: firestore);

      expect(await repository.fetchUser('missing'), isNull);

      await firestore.collection('users').doc('player-1').set(
            _user(uid: 'player-1', name: 'Awa Traore').toMap(),
          );

      final user = await repository.fetchUser('player-1');
      expect(user?.uid, 'player-1');
      expect(user?.nom, 'Awa Traore');
    });

    test('updateProfilePatch sanitizes values and deep merges advanced profile',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repository = ProfileRepository(firestore: firestore);
      final user = _user(uid: 'player-1', name: 'Original');

      await firestore.collection('users').doc(user.uid).set({
        ...user.toMap(),
        'phone': '+225000000',
        'playerProfile': {
          'physical': {
            'heightCm': 181,
            'weightKg': 74,
          },
          'skills': ['pace'],
        },
      });

      final result = await repository.updateProfilePatch(user.uid, {
        'nom': '  Nouveau nom  ',
        'phone': ProfileRepository.deleteField,
        'bio': '   ',
        'playerProfile': {
          'physical': {'weightKg': 77},
          'availability': {'open': true},
        },
      });

      final data =
          (await firestore.collection('users').doc(user.uid).get()).data()!;
      final playerProfile =
          Map<String, dynamic>.from(data['playerProfile'] as Map);
      final physical =
          Map<String, dynamic>.from(playerProfile['physical'] as Map);

      expect(data['nom'], 'Nouveau nom');
      expect(data.containsKey('phone'), isFalse);
      expect(data['bio'], isNull);
      expect(physical['heightCm'], 181);
      expect(physical['weightKg'], 77);
      expect(playerProfile['skills'], ['pace']);
      expect(playerProfile['availability'], {'open': true});
      expect(result.appliedPatch['phone'], isA<ProfileFieldDelete>());
      expect(result.appliedPatch['bio'], isNull);
    });

    test('fetchUserVideos returns ready playable videos by update date',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repository = ProfileRepository(firestore: firestore);

      await firestore.collection('videos').doc('ignored-processing').set(
            _videoDoc(
              uid: 'player-1',
              status: 'processing',
              updatedAt: DateTime(2026, 1, 4),
            ),
          );
      await firestore.collection('videos').doc('newer').set(
            _videoDoc(
              uid: 'player-1',
              status: 'ready',
              updatedAt: DateTime(2026, 1, 3),
            ),
          );
      await firestore.collection('videos').doc('older').set(
            _videoDoc(
              uid: 'player-1',
              status: 'ready',
              updatedAt: DateTime(2026, 1, 2),
            ),
          );
      await firestore.collection('videos').doc('other-user').set(
            _videoDoc(
              uid: 'player-2',
              status: 'ready',
              updatedAt: DateTime(2026, 1, 5),
            ),
          );

      final firstPage = await repository.fetchUserVideos(
        uid: 'player-1',
        limit: 1,
      );
      final fullPage = await repository.fetchUserVideos(
        uid: 'player-1',
        limit: 20,
      );

      expect(firstPage.fetchedCount, 1);
      expect(firstPage.videos.single.id, 'newer');
      expect(firstPage.cursor, isNotNull);
      expect(fullPage.fetchedCount, 2);
      expect(fullPage.videos.map((video) => video.id), ['newer', 'older']);
    });
  });
}

AppUser _user({required String uid, required String name}) {
  return AppUser(
    uid: uid,
    nom: name,
    email: '$uid@example.com',
    role: 'joueur',
    photoProfil: '',
    estActif: true,
    emailVerified: true,
    followers: 0,
    followings: 0,
    dateInscription: DateTime(2026, 1, 1),
    dernierLogin: DateTime(2026, 1, 1),
    followersList: const <String>[],
    followingsList: const <String>[],
  );
}

Map<String, dynamic> _videoDoc({
  required String uid,
  required String status,
  required DateTime updatedAt,
}) {
  return {
    'uid': uid,
    'status': status,
    'updatedAt': Timestamp.fromDate(updatedAt),
    'videoUrl': 'https://cdn.adfoot.test/$uid-$status.mp4',
    'thumbnail': 'https://cdn.adfoot.test/thumb.jpg',
    'description': 'Video',
    'caption': 'Caption',
    'profilePhoto': '',
  };
}
