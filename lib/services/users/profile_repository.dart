import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProfileFieldDelete {
  const ProfileFieldDelete._();
}

class ProfilePatchWriteResult {
  const ProfilePatchWriteResult({required this.appliedPatch});

  final Map<String, dynamic> appliedPatch;
}

class ProfileVideoCursor {
  const ProfileVideoCursor._(this.snapshot);

  final DocumentSnapshot<Map<String, dynamic>> snapshot;
}

class ProfileVideoPage {
  const ProfileVideoPage({
    required this.videos,
    required this.cursor,
    required this.fetchedCount,
  });

  final List<Video> videos;
  final ProfileVideoCursor? cursor;
  final int fetchedCount;
}

class _SanitizedProfilePatch {
  const _SanitizedProfilePatch({
    required this.firestorePatch,
    required this.localPatch,
  });

  final Map<String, dynamic> firestorePatch;
  final Map<String, dynamic> localPatch;
}

class ProfileRepository {
  ProfileRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storageOverride = storage,
        _authOverride = auth;

  static const ProfileFieldDelete deleteField = ProfileFieldDelete._();
  static const Duration firestoreReadTimeout = Duration(seconds: 12);
  static const Duration firestoreWriteTimeout = Duration(seconds: 15);
  static const Duration storageWriteTimeout = Duration(seconds: 45);
  static const String _profileInvalidationReason = 'profile_updated_by_user';
  static const Set<String> _advancedProfileKeys = {
    'playerProfile',
    'clubProfile',
    'agentProfile',
    'eventOrganizerProfile',
  };
  static const Set<String> _trustSensitiveProfileKeys = {
    'nom',
    'phone',
    'languages',
    'bio',
    'birthDate',
    'position',
    'team',
    'clubActuel',
    'nombreDeMatchs',
    'buts',
    'assistances',
    'performances',
    'nomClub',
    'ligue',
    'entreprise',
    'nombreDeRecrutements',
    'country',
    'city',
    'region',
    'openToOpportunities',
    'playerProfile',
    'clubProfile',
    'agentProfile',
    'eventOrganizerProfile',
    'photoProfil',
    'cvUrl',
  };

  final FirebaseFirestore _firestore;
  final FirebaseStorage? _storageOverride;
  final FirebaseAuth? _authOverride;

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _videosCollection =>
      _firestore.collection('videos');

  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  String? get currentAuthUid => _auth.currentUser?.uid;

  static bool isPermissionDenied(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }

  static bool isUnauthorized(Object error) {
    return error is FirebaseException && error.code == 'unauthorized';
  }

  static bool isTransientFirestoreError(Object error) {
    if (error is! FirebaseException) {
      return false;
    }

    switch (error.code) {
      case 'unavailable':
      case 'deadline-exceeded':
      case 'aborted':
      case 'cancelled':
      case 'resource-exhausted':
      case 'internal':
        return true;
    }

    final message = error.message?.toLowerCase() ?? '';
    return message.contains('i/o error') ||
        message.contains('software caused connection abort') ||
        message.contains('connection abort') ||
        message.contains('network') ||
        message.contains('socket') ||
        message.contains('timeout');
  }

  Future<AppUser?> fetchUser(String uid) async {
    final doc = await _getWithRetry(_usersCollection.doc(uid));
    if (!doc.exists) {
      return null;
    }

    final data = doc.data();
    if (data == null) {
      return null;
    }

    return AppUser.fromMap(data);
  }

  Stream<AppUser?> watchUser(String uid) {
    return _usersCollection.doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return null;
      }
      return AppUser.fromMap(data);
    });
  }

  Future<void> saveUserProfile(AppUser updatedUser) async {
    final data = updatedUser.toMap();
    await _appendVerificationInvalidationIfCurrentProfileIsVerified(
      uid: updatedUser.uid,
      firestorePatch: data,
    );

    return _usersCollection
        .doc(updatedUser.uid)
        .set(data, SetOptions(merge: true))
        .timeout(firestoreWriteTimeout);
  }

  Future<ProfilePatchWriteResult> updateProfilePatch(
    String uid,
    Map<String, dynamic> patch,
  ) async {
    if (patch.isEmpty) {
      return const ProfilePatchWriteResult(appliedPatch: <String, dynamic>{});
    }

    final sanitized = _sanitizePatch(patch);
    if (sanitized.firestorePatch.isEmpty) {
      return const ProfilePatchWriteResult(appliedPatch: <String, dynamic>{});
    }

    final firestorePatch = Map<String, dynamic>.from(sanitized.firestorePatch);
    final localPatch = Map<String, dynamic>.from(sanitized.localPatch);
    Map<String, dynamic>? existingData;
    Future<Map<String, dynamic>> loadExistingData() async {
      if (existingData != null) {
        return existingData!;
      }

      final doc = await _getWithRetry(_usersCollection.doc(uid));
      existingData = doc.data() ?? <String, dynamic>{};
      return existingData!;
    }

    final needsDeepMerge =
        firestorePatch.keys.any(_advancedProfileKeys.contains);
    if (needsDeepMerge) {
      final existing = await loadExistingData();

      for (final key in _advancedProfileKeys) {
        if (!firestorePatch.containsKey(key)) {
          continue;
        }

        final incomingLocal = localPatch[key];
        if (incomingLocal is ProfileFieldDelete || incomingLocal is! Map) {
          continue;
        }

        final old = existing[key];
        final merged = old is Map
            ? _deepMergeMap(
                Map<String, dynamic>.from(old),
                Map<String, dynamic>.from(incomingLocal),
              )
            : Map<String, dynamic>.from(incomingLocal);
        firestorePatch[key] = merged;
        localPatch[key] = merged;
      }
    }

    if (firestorePatch.keys.any(_trustSensitiveProfileKeys.contains)) {
      await _appendVerificationInvalidationIfCurrentProfileIsVerified(
        uid: uid,
        firestorePatch: firestorePatch,
        localPatch: localPatch,
        existingData: await loadExistingData(),
      );
    }

    await _usersCollection
        .doc(uid)
        .update(firestorePatch)
        .timeout(firestoreWriteTimeout);

    return ProfilePatchWriteResult(appliedPatch: localPatch);
  }

  Future<String> updateProfilePhoto(String uid, String photoPath) async {
    final ref = _storage.ref('profilePhotos/$uid');
    await ref
        .putFile(
          File(photoPath),
          SettableMetadata(contentType: 'image/jpeg'),
        )
        .timeout(storageWriteTimeout);
    final url = await ref.getDownloadURL().timeout(firestoreReadTimeout);

    final patch = <String, dynamic>{
      'photoProfil': url,
    };
    await _appendVerificationInvalidationIfCurrentProfileIsVerified(
      uid: uid,
      firestorePatch: patch,
    );

    await _usersCollection
        .doc(uid)
        .update(patch)
        .timeout(firestoreWriteTimeout);

    return url;
  }

  Future<ProfileVideoPage> fetchUserVideos({
    required String uid,
    required int limit,
    ProfileVideoCursor? after,
  }) async {
    Query<Map<String, dynamic>> query = _videosCollection
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'ready')
        .orderBy('updatedAt', descending: true)
        .limit(limit);

    if (after != null) {
      query = query.startAfterDocument(after.snapshot);
    }

    final snap = await query.get().timeout(firestoreReadTimeout);
    final videos = snap.docs
        .map(Video.fromDoc)
        .where((video) => video.videoUrl.isNotEmpty)
        .toList(growable: false);

    return ProfileVideoPage(
      videos: videos,
      cursor: snap.docs.isEmpty ? after : ProfileVideoCursor._(snap.docs.last),
      fetchedCount: snap.docs.length,
    );
  }

  Future<String> uploadCvPdf(
    String uid, {
    File? pdfFile,
    Uint8List? pdfBytes,
    String? fileName,
    String? previousCvUrl,
  }) async {
    if ((pdfFile == null && pdfBytes == null) ||
        (pdfBytes != null && pdfBytes.isEmpty)) {
      throw ArgumentError('CV payload is empty.');
    }

    final targetFileName = fileName?.trim().isNotEmpty == true
        ? fileName!.trim()
        : 'cv_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final storagePath = 'cvs/$uid/$targetFileName';
    final ref = _storage.ref(storagePath);
    final metadata = SettableMetadata(contentType: 'application/pdf');

    final uploadTask = pdfBytes != null
        ? await ref.putData(pdfBytes, metadata).timeout(storageWriteTimeout)
        : await ref.putFile(pdfFile!, metadata).timeout(storageWriteTimeout);
    final url =
        await uploadTask.ref.getDownloadURL().timeout(firestoreReadTimeout);

    final patch = <String, dynamic>{'cvUrl': url};
    await _appendVerificationInvalidationIfCurrentProfileIsVerified(
      uid: uid,
      firestorePatch: patch,
    );

    await _usersCollection
        .doc(uid)
        .update(patch)
        .timeout(firestoreWriteTimeout);

    if (previousCvUrl != null &&
        previousCvUrl.isNotEmpty &&
        previousCvUrl != url) {
      try {
        await _storage.refFromURL(previousCvUrl).delete();
      } catch (cleanupError, cleanupStackTrace) {
        developer.log(
          'uploadCvPdf previous CV cleanup warning',
          name: 'ProfileRepository.uploadCvPdf',
          error: cleanupError,
          stackTrace: cleanupStackTrace,
        );
      }
    }

    return url;
  }

  Future<void> deleteCv(String uid, {String? cvUrl}) async {
    if (cvUrl != null && cvUrl.isNotEmpty) {
      await _storage.refFromURL(cvUrl).delete().timeout(storageWriteTimeout);
    }

    final patch = <String, dynamic>{
      'cvUrl': FieldValue.delete(),
    };
    await _appendVerificationInvalidationIfCurrentProfileIsVerified(
      uid: uid,
      firestorePatch: patch,
    );

    await _usersCollection
        .doc(uid)
        .update(patch)
        .timeout(firestoreWriteTimeout);
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getWithRetry(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    int attempt = 0;
    while (attempt < 3) {
      try {
        return await ref.get().timeout(firestoreReadTimeout);
      } catch (_) {
        attempt++;
        if (attempt >= 3) {
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    throw Exception('Firestore retry failed');
  }

  Future<void> _appendVerificationInvalidationIfCurrentProfileIsVerified({
    required String uid,
    required Map<String, dynamic> firestorePatch,
    Map<String, dynamic>? localPatch,
    Map<String, dynamic>? existingData,
  }) async {
    final data = existingData ??
        (await _getWithRetry(_usersCollection.doc(uid))).data() ??
        <String, dynamic>{};

    if (!_isProfileCurrentlyVerified(data)) {
      return;
    }

    final localNow = DateTime.now();
    firestorePatch.addAll({
      'profileVerified': false,
      'profileVerificationStatus': 'pending',
      'profileVerificationUpdatedAt': FieldValue.serverTimestamp(),
      'profileVerificationUpdatedBy': uid,
      'profileVerificationInvalidatedAt': FieldValue.serverTimestamp(),
      'profileVerificationInvalidatedBy': uid,
      'profileVerificationInvalidationReason': _profileInvalidationReason,
    });

    localPatch?.addAll({
      'profileVerified': false,
      'profileVerificationStatus': 'pending',
      'profileVerificationUpdatedAt': localNow,
      'profileVerificationUpdatedBy': uid,
      'profileVerificationInvalidatedAt': localNow,
      'profileVerificationInvalidatedBy': uid,
      'profileVerificationInvalidationReason': _profileInvalidationReason,
    });
  }

  static bool _isProfileCurrentlyVerified(Map<String, dynamic> data) {
    final status =
        data['profileVerificationStatus']?.toString().trim().toLowerCase();
    return data['profileVerified'] == true || status == 'verified';
  }

  static _SanitizedProfilePatch _sanitizePatch(Map<String, dynamic> patch) {
    final firestorePatch = <String, dynamic>{};
    final localPatch = <String, dynamic>{};

    void addIfValid(String key, dynamic value) {
      if (value == null) {
        return;
      }

      if (value is ProfileFieldDelete) {
        firestorePatch[key] = FieldValue.delete();
        localPatch[key] = deleteField;
        return;
      }

      if (value is FieldValue) {
        firestorePatch[key] = value;
        localPatch[key] = deleteField;
        return;
      }

      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) {
          return;
        }
        firestorePatch[key] = trimmed;
        localPatch[key] = trimmed;
        return;
      }

      if (value is List) {
        if (value.isEmpty) {
          return;
        }
        firestorePatch[key] = value;
        localPatch[key] = value;
        return;
      }

      if (value is Map) {
        if (value.isEmpty) {
          return;
        }
        final mapped = Map<String, dynamic>.from(value);
        firestorePatch[key] = mapped;
        localPatch[key] = mapped;
        return;
      }

      firestorePatch[key] = value;
      localPatch[key] = value;
    }

    patch.forEach(addIfValid);
    return _SanitizedProfilePatch(
      firestorePatch: firestorePatch,
      localPatch: localPatch,
    );
  }

  static Map<String, dynamic> _deepMergeMap(
    Map<String, dynamic> base,
    Map<String, dynamic> incoming,
  ) {
    final result = Map<String, dynamic>.from(base);

    incoming.forEach((key, value) {
      if (value == null) {
        return;
      }
      final old = result[key];
      if (old is Map && value is Map) {
        result[key] = _deepMergeMap(
          Map<String, dynamic>.from(old),
          Map<String, dynamic>.from(value),
        );
      } else {
        result[key] = value;
      }
    });

    return result;
  }
}
