import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/users/profile_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProfileRepository', () {
    test(
      'fetchUser returns null for missing profiles and parses existing users',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = _repository(firestore, uid: 'player-1');

        expect(await repository.fetchUser('missing'), isNull);

        await firestore
            .collection('users')
            .doc('player-1')
            .set(_user(uid: 'player-1', name: 'Awa Traore').toMap());

        final user = await repository.fetchUser('player-1');
        expect(user?.uid, 'player-1');
        expect(user?.nom, 'Awa Traore');
      },
    );

    test('fetchUser parses admin profile verification metadata', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = _repository(firestore, uid: 'player-1');

      await firestore.collection('users').doc('player-verified').set({
        ..._user(uid: 'player-verified', name: 'Verified Player').toMap(),
        'position': 'Milieu',
        'team': 'Academy A',
        'profileVerified': true,
        'profileVerificationStatus': 'verified',
        'profileVerifiedAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
        'profileVerifiedBy': 'admin-1',
        'profileVerificationNote': 'Identité contrôlée',
        'profileVerificationInvalidatedAt': Timestamp.fromDate(
          DateTime.utc(2026, 6, 5),
        ),
        'profileVerificationInvalidatedBy': 'player-verified',
        'profileVerificationInvalidationReason': 'profile_updated_by_user',
      });

      final user = await repository.fetchUser('player-verified');

      expect(user?.profileLevelLabel, 'Profil complet');
      expect(user?.profileVerified, isTrue);
      expect(user?.isProfileTrusted, isTrue);
      expect(user?.profileTrustLabel, 'Vérifié par Adfoot');
      expect(user?.profileVerificationStatusLabel, 'Vérifié par admin');
      expect(user?.profileVerifiedBy, 'admin-1');
      expect(user?.profileVerificationNote, 'Identité contrôlée');
      expect(
        user?.profileVerificationInvalidatedAt?.toUtc(),
        DateTime.utc(2026, 6, 5),
      );
      expect(user?.profileVerificationInvalidatedBy, 'player-verified');
      expect(
        user?.profileVerificationInvalidationReason,
        'profile_updated_by_user',
      );
    });

    test(
      'updateProfilePatch sanitizes values and deep merges advanced profile',
      () async {
        final firestore = FakeFirebaseFirestore();
        final user = _user(uid: 'player-1', name: 'Original');
        final repository = _repository(firestore, uid: user.uid);

        await firestore.collection('users').doc(user.uid).set({
          ...user.toMap(),
          'phone': '+225000000',
          'playerProfile': {
            'physical': {'heightCm': 181, 'weightKg': 74},
            'skills': ['pace'],
          },
        });

        final result = await repository.updateProfilePatch(user.uid, {
          'nom': '  Nouveau nom  ',
          'phone': ProfileRepository.deleteField,
          'bio': '   ',
          'city': '  Abidjan  ',
          'region': '  Lagunes  ',
          'country': '  Côte d’Ivoire  ',
          'playerProfile': {
            'physical': {'weightKg': 77},
            'availability': {'open': true},
          },
        });

        final data = (await firestore.collection('users').doc(user.uid).get())
            .data()!;
        final playerProfile = Map<String, dynamic>.from(
          data['playerProfile'] as Map,
        );
        final physical = Map<String, dynamic>.from(
          playerProfile['physical'] as Map,
        );

        expect(data['nom'], 'Nouveau nom');
        expect(data.containsKey('phone'), isFalse);
        expect(data['bio'], isNull);
        expect(data['city'], 'Abidjan');
        expect(data['region'], 'Lagunes');
        expect(data['country'], 'Côte d’Ivoire');
        expect(physical['heightCm'], 181);
        expect(physical['weightKg'], 77);
        expect(playerProfile['skills'], ['pace']);
        expect(playerProfile['availability'], {'open': true});
        expect(result.appliedPatch['phone'], isA<ProfileFieldDelete>());
        expect(result.appliedPatch['bio'], isNull);
      },
    );

    test(
      'updateProfilePatch removes empty nested advanced profile fields',
      () async {
        final firestore = FakeFirebaseFirestore();
        final user = _user(uid: 'player-cleanup', name: 'Original');
        final repository = _repository(firestore, uid: user.uid);

        await firestore.collection('users').doc(user.uid).set({
          ...user.toMap(),
          'playerProfile': {
            'physical': {
              'heightCm': 181,
              'weightKg': 74,
              'strongFoot': 'right',
            },
            'positions': ['ailier'],
            'skills': ['pace'],
            'stats': {'goals': 12, 'assists': 5},
            'availability': {
              'open': true,
              'regions': ['Abidjan'],
            },
          },
        });

        final result = await repository.updateProfilePatch(user.uid, {
          'playerProfile': {
            'physical': {'heightCm': null, 'weightKg': 80, 'strongFoot': ' '},
            'positions': [],
            'skills': [' finition ', ' '],
            'stats': {'goals': null},
            'availability': {'open': false, 'regions': []},
          },
        });

        final data = (await firestore.collection('users').doc(user.uid).get())
            .data()!;
        final playerProfile = Map<String, dynamic>.from(
          data['playerProfile'] as Map,
        );
        final physical = Map<String, dynamic>.from(
          playerProfile['physical'] as Map,
        );
        final stats = Map<String, dynamic>.from(playerProfile['stats'] as Map);

        expect(physical.containsKey('heightCm'), isFalse);
        expect(physical['weightKg'], 80);
        expect(physical.containsKey('strongFoot'), isFalse);
        expect(playerProfile.containsKey('positions'), isFalse);
        expect(playerProfile['skills'], ['finition']);
        expect(stats, {'assists': 5});
        expect(playerProfile['availability'], {'open': false});

        final appliedProfile = Map<String, dynamic>.from(
          result.appliedPatch['playerProfile'] as Map,
        );
        expect(appliedProfile['availability'], {'open': false});
      },
    );

    test('hasAdvancedProfile ignores empty shells and false-only sections', () {
      final emptyShell = _user(uid: 'player-empty', name: 'Empty')
        ..playerProfile = {
          'availability': {'open': false, 'regions': <String>[]},
        };
      final meaningfulStats = _user(uid: 'player-stats', name: 'Stats')
        ..playerProfile = {
          'stats': {'goals': 0},
        };

      expect(emptyShell.hasAdvancedProfile, isFalse);
      expect(meaningfulStats.hasAdvancedProfile, isTrue);
    });

    test(
      'updateProfilePatch invalidates verified trust profile changes',
      () async {
        final firestore = FakeFirebaseFirestore();
        final user = _user(uid: 'player-verified', name: 'Original');
        final repository = _repository(firestore, uid: user.uid);

        await firestore.collection('users').doc(user.uid).set({
          ...user.toMap(),
          'position': 'Milieu',
          'team': 'Academy A',
          'profileVerified': true,
          'profileVerificationStatus': 'verified',
          'profileVerifiedAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
          'profileVerifiedBy': 'admin-1',
        });

        final result = await repository.updateProfilePatch(user.uid, {
          'nom': '  Nouveau nom  ',
        });

        final data = (await firestore.collection('users').doc(user.uid).get())
            .data()!;

        expect(data['nom'], 'Nouveau nom');
        expect(data['profileVerified'], isFalse);
        expect(data['profileVerificationStatus'], 'pending');
        expect(data['profileVerificationUpdatedBy'], user.uid);
        expect(data['profileVerificationInvalidatedBy'], user.uid);
        expect(
          data['profileVerificationInvalidationReason'],
          'profile_updated_by_user',
        );
        expect(result.appliedPatch['profileVerified'], isFalse);
        expect(result.appliedPatch['profileVerificationStatus'], 'pending');
      },
    );

    test(
      'updateProfilePatch keeps verification for privacy-only changes',
      () async {
        final firestore = FakeFirebaseFirestore();
        final user = _user(uid: 'player-private', name: 'Private Player');
        final repository = _repository(firestore, uid: user.uid);

        await firestore.collection('users').doc(user.uid).set({
          ...user.toMap(),
          'position': 'Milieu',
          'team': 'Academy A',
          'profileVerified': true,
          'profileVerificationStatus': 'verified',
          'profileVerifiedAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
          'profileVerifiedBy': 'admin-1',
        });

        await repository.updateProfilePatch(user.uid, {
          'profilePublic': false,
          'allowMessages': false,
        });

        final data = (await firestore.collection('users').doc(user.uid).get())
            .data()!;

        expect(data['profilePublic'], isFalse);
        expect(data['allowMessages'], isFalse);
        expect(data['profileVerified'], isTrue);
        expect(data['profileVerificationStatus'], 'verified');
        expect(data['profileVerificationInvalidatedAt'], isNull);
      },
    );

    test(
      'fetchUserVideos returns ready playable videos by update date',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = _repository(firestore, uid: 'player-1');

        await firestore
            .collection('videos')
            .doc('ignored-processing')
            .set(
              _videoDoc(
                uid: 'player-1',
                status: 'processing',
                updatedAt: DateTime(2026, 1, 4),
              ),
            );
        await firestore
            .collection('videos')
            .doc('newer')
            .set(
              _videoDoc(
                uid: 'player-1',
                status: 'ready',
                updatedAt: DateTime(2026, 1, 3),
              ),
            );
        await firestore
            .collection('videos')
            .doc('older')
            .set(
              _videoDoc(
                uid: 'player-1',
                status: 'ready',
                updatedAt: DateTime(2026, 1, 2),
              ),
            );
        await firestore
            .collection('videos')
            .doc('other-user')
            .set(
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
      },
    );

    test('fetchUserVideos accepts legacy playable video URL aliases', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = _repository(firestore, uid: 'player-verified');

      await firestore.collection('videos').doc('legacy-url').set({
        'uid': 'player-1',
        'status': 'ready',
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'downloadUrl': 'https://cdn.adfoot.test/legacy-url.mp4',
        'thumbnail_url': 'https://cdn.adfoot.test/legacy-thumb.jpg',
        'description': 'Legacy Video',
        'caption': 'Legacy Caption',
        'profilePhoto': '',
      });

      final page = await repository.fetchUserVideos(uid: 'player-1', limit: 20);

      expect(page.videos.single.id, 'legacy-url');
      expect(
        page.videos.single.videoUrl,
        'https://cdn.adfoot.test/legacy-url.mp4',
      );
      expect(
        page.videos.single.thumbnailUrl,
        'https://cdn.adfoot.test/legacy-thumb.jpg',
      );
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

ProfileRepository _repository(
  FakeFirebaseFirestore firestore, {
  required String uid,
}) {
  return ProfileRepository(
    firestore: firestore,
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: '$uid@example.com'),
    ),
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
