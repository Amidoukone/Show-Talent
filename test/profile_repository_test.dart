import 'package:adfoot/controller/profile_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/users/profile_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // ProfileController's constructor eagerly touches VideoManager (for its
  // per-profile playback context), which needs a Flutter test binding and
  // mocked SharedPreferences before it can be built off the widget tree.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

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
          'playerProfile': {
            'physical': {'heightCm': 181, 'weightKg': 74},
            'skills': ['pace'],
          },
        });
        final contactRef = firestore
            .collection('users')
            .doc(user.uid)
            .collection('private')
            .doc('contact');
        await contactRef.set({'phone': '+225000000'});

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
        final contactData = (await contactRef.get()).data() ?? {};

        expect(data['nom'], 'Nouveau nom');
        expect(data.containsKey('phone'), isFalse);
        expect(contactData.containsKey('phone'), isFalse);
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

    test('updateProfilePatch persists a list of maps with a blank sub-field '
        'without throwing (club recruitment needs with no priority)', () async {
      final firestore = FakeFirebaseFirestore();
      final user = _user(uid: 'club-1', name: 'Club Original');
      final repository = _repository(firestore, uid: user.uid);

      await firestore.collection('users').doc(user.uid).set(user.toMap());

      // Mirrors ClubAdvancedFormState._parseNeeds(): an entry typed
      // without a ":" yields a null priority.
      final result = await repository.updateProfilePatch(user.uid, {
        'clubProfile': {
          'structureType': 'Club amateur',
          'needs': [
            {'position': 'Gardien', 'priority': '1'},
            {'position': 'Attaquant', 'priority': null},
          ],
        },
      });

      final data = (await firestore.collection('users').doc(user.uid).get())
          .data()!;
      final clubProfile = Map<String, dynamic>.from(data['clubProfile'] as Map);
      final needs = List<Map<String, dynamic>>.from(
        (clubProfile['needs'] as List).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );

      expect(needs, [
        {'position': 'Gardien', 'priority': '1'},
        {'position': 'Attaquant'},
      ]);
      expect(result.appliedPatch['clubProfile'], isNotNull);
    });

    test('hasAdvancedProfile ignores empty shells but keeps a real zero', () {
      // Meme intention qu'avant la refonte, exprimee sur le modele type : une
      // coquille vide n'est pas un profil avance, mais un zero reellement
      // saisi en est un. « 0 but sur la saison » est une information ; un
      // dossier sans aucun champ n'en est pas une.
      AppUser player(Map<String, dynamic> football) =>
          AppUser.fromMap(<String, dynamic>{
            'uid': 'p1',
            'nom': 'Awa Traore',
            'role': 'joueur',
            ...football,
          });

      final emptyShell = player(<String, dynamic>{
        'positionCodes': <String>[],
        'currentSeason': <String, dynamic>{},
      });
      final unreadable = player(<String, dynamic>{
        'positionCodes': <String>['SWEEPER'],
        'strongFoot': 'sideways',
      });
      final realZero = player(<String, dynamic>{
        'currentSeason': <String, dynamic>{'goals': 0},
      });

      expect(emptyShell.hasAdvancedProfile, isFalse);
      // Un code illisible ne compte pas non plus : il ne remplit rien.
      expect(unreadable.hasAdvancedProfile, isFalse);
      expect(realZero.hasAdvancedProfile, isTrue);
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

  group('Basic profile edit -> profile screen end-to-end sync', () {
    // Mirrors the exact patch shape EditProfileScreen._save() sends
    // (lib/screens/edit_profil_screen.dart), and asserts on the exact
    // fields ProfileScreen reads (user.nom/phone/bio/city/region/country/
    // birthDate/position/team) — both from the in-memory state right after
    // the edit (what the screen shows immediately) and from a fresh
    // Firestore read (what a cold relaunch / different session shows).
    test(
      'every basic-edit field (name, contact, bio, location, birth date) '
      'round-trips to both the in-memory user and a fresh Firestore fetch',
      () async {
        final firestore = FakeFirebaseFirestore();
        final user = _user(uid: 'player-sync', name: 'Original Name');
        final repository = _repository(firestore, uid: user.uid);

        await firestore.collection('users').doc(user.uid).set(user.toMap());

        final controller = ProfileController(profileRepository: repository);
        controller.user = await repository.fetchUser(
          user.uid,
          includePrivateFields: true,
        );

        await controller.updateProfilePatch(user.uid, {
          'nom': 'Nom Modifie',
          'phone': '+2250700000000',
          'languages': ['Français', 'Anglais'],
          'bio': 'Nouvelle présentation professionnelle',
          'city': 'Abidjan',
          'region': 'Lagunes',
          'country': 'Côte d’Ivoire',
          'birthDate': DateTime.utc(1999, 5, 12),
          'position': 'Milieu',
          'team': 'Academy A',
          'clubActuel': 'Academy A',
        });

        // What ProfileScreen reads immediately after Navigator.pop(true),
        // from the optimistically-updated in-memory user.
        expect(controller.user?.nom, 'Nom Modifie');
        expect(controller.user?.phone, '+2250700000000');
        expect(controller.user?.languages, ['Français', 'Anglais']);
        expect(controller.user?.bio, 'Nouvelle présentation professionnelle');
        expect(controller.user?.city, 'Abidjan');
        expect(controller.user?.region, 'Lagunes');
        expect(controller.user?.country, 'Côte d’Ivoire');
        expect(controller.user?.birthDate?.toUtc(), DateTime.utc(1999, 5, 12));
        expect(controller.user?.position, 'Milieu');
        expect(controller.user?.team, 'Academy A');

        // What a fresh screen load (cold relaunch, or another session)
        // reads straight from Firestore, independent of any in-memory
        // optimistic state.
        final reloaded = await repository.fetchUser(
          user.uid,
          includePrivateFields: true,
        );
        expect(reloaded?.nom, 'Nom Modifie');
        expect(reloaded?.phone, '+2250700000000');
        expect(reloaded?.bio, 'Nouvelle présentation professionnelle');
        expect(reloaded?.city, 'Abidjan');
        expect(reloaded?.region, 'Lagunes');
        expect(reloaded?.country, 'Côte d’Ivoire');
        expect(reloaded?.birthDate?.toUtc(), DateTime.utc(1999, 5, 12));
      },
    );

    test('watchUser keeps emitting the current user when only the private '
        'contact doc changes (phone/birthDate-only edits)', () async {
      final firestore = FakeFirebaseFirestore();
      final user = _user(uid: 'player-stream', name: 'Stream User');
      final repository = _repository(firestore, uid: user.uid);

      await firestore.collection('users').doc(user.uid).set(user.toMap());

      final events = <AppUser?>[];
      final subscription = repository
          .watchUser(user.uid, includePrivateFields: true)
          .listen(events.add);
      addTearDown(subscription.cancel);

      await Future<void>.delayed(Duration.zero);

      // Exactly what a phone/birthDate-only edit does server-side: only
      // users/{uid}/private/contact changes, the parent users/{uid} doc
      // is untouched.
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('private')
          .doc('contact')
          .set({'phone': '+2250700000001'}, SetOptions(merge: true));

      await Future<void>.delayed(Duration.zero);

      expect(events.any((u) => u?.phone == '+2250700000001'), isTrue);
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
    appCheckReady: ({required forceRefresh, timeout}) async => true,
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
