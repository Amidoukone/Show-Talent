import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../app_logger.dart';
import '../app_check_service.dart';

class ProfileFieldDelete {
  const ProfileFieldDelete._();
}

class _ProfileNestedFieldDelete {
  const _ProfileNestedFieldDelete();
}

class ProfilePatchWriteResult {
  const ProfilePatchWriteResult({required this.appliedPatch});

  final Map<String, dynamic> appliedPatch;
}

class CvUploadValidationException implements Exception {
  const CvUploadValidationException(this.message);

  final String message;

  @override
  String toString() => message;
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

typedef AppCheckReadyCallback =
    Future<bool> Function({required bool forceRefresh, Duration? timeout});

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
    AppCheckReadyCallback? appCheckReady,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storageOverride = storage,
       _authOverride = auth,
       _appCheckReady = appCheckReady ?? _defaultAppCheckReady;

  static const ProfileFieldDelete deleteField = ProfileFieldDelete._();
  static const Duration firestoreReadTimeout = Duration(seconds: 20);
  static const Duration firestoreWriteTimeout = Duration(seconds: 30);
  static const Duration storageWriteTimeout = Duration(seconds: 90);
  // Firestore/Storage attach the current Firebase Auth token themselves. This
  // preflight only verifies that a matching signed-in user is still present;
  // it must not force a network token refresh before every profile write.
  static const Duration authRefreshTimeout = Duration(seconds: 10);
  // Only bounds the background warm-up in _warmUpAppCheckForWrite(); no write
  // ever waits on it.
  static const Duration appCheckWriteTimeout = Duration(seconds: 6);
  static const int maxCvPdfBytes = 5 * 1024 * 1024;
  static const String _profileInvalidationReason = 'profile_updated_by_user';
  static const List<int> _pdfHeader = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];
  static const Set<String> _advancedProfileKeys = {
    'playerProfile',
    'clubProfile',
    'agentProfile',
    'eventOrganizerProfile',
  };
  static const _deleteNestedProfileField = _ProfileNestedFieldDelete();
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
  // Fields that must land in users/{uid}/private/contact instead of the
  // main doc. Still trust-sensitive (see above) — moving where a field is
  // physically stored doesn't change whether editing it should invalidate
  // an existing verification. cvUrl deliberately stays out of this set and
  // on the main doc — see toEmbeddedMap()/toMap() in AppUser for why.
  static const Set<String> _privateContactKeys = {'phone', 'birthDate'};

  final FirebaseFirestore _firestore;
  final FirebaseStorage? _storageOverride;
  final FirebaseAuth? _authOverride;
  final AppCheckReadyCallback _appCheckReady;

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _videosCollection =>
      _firestore.collection('videos');

  DocumentReference<Map<String, dynamic>> _privateContactDoc(String uid) =>
      _usersCollection.doc(uid).collection('private').doc('contact');

  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  String? get currentAuthUid => _auth.currentUser?.uid;

  static Future<bool> _defaultAppCheckReady({
    required bool forceRefresh,
    Duration? timeout,
  }) {
    return AppCheckService.ensureReady(
      forceRefresh: forceRefresh,
      timeout: timeout,
    );
  }

  // Fire-and-forget. App Check is UNENFORCED on both firestore.googleapis.com
  // and firebasestorage.googleapis.com for this project, so a token is not
  // required for any write below — it is only nudged along so the token is
  // fresher for the callables that do read it.
  //
  // This used to *await* a token and throw
  // "Connexion sécurisée indisponible" when none arrived. That turned a
  // service Firestore does not even consult into a hard blocker on saving a
  // profile, uploading a photo or attaching a CV, on every device where Play
  // Integrity attestation fails.
  void _warmUpAppCheckForWrite() {
    unawaited(_appCheckReady(forceRefresh: false, timeout: appCheckWriteTimeout));
  }

  Future<void> _ensureAuthenticatedOwner(String uid) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != uid) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'permission-denied',
        message: 'Authenticated profile owner required.',
      );
    }

    _warmUpAppCheckForWrite();

    try {
      await currentUser.getIdToken().timeout(authRefreshTimeout);
    } on TimeoutException catch (error, stackTrace) {
      _logAuthTokenWarmupWarning(error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      if (!_isTransientAuthTokenRefreshError(error)) {
        rethrow;
      }
      _logAuthTokenWarmupWarning(error, stackTrace);
    }
  }

  static void _logAuthTokenWarmupWarning(Object error, StackTrace? stackTrace) {
    developer.log(
      'auth token warm-up warning; continuing with Firebase SDK token handling',
      name: 'ProfileRepository._ensureAuthenticatedOwner',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static bool _isTransientAuthTokenRefreshError(FirebaseException error) {
    switch (error.code) {
      case 'network-request-failed':
      case 'timeout':
      case 'too-many-requests':
      case 'internal-error':
      case 'unknown':
        return true;
      default:
        return false;
    }
  }

  static bool isPermissionDenied(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }

  static bool isUnauthorized(Object error) {
    return error is FirebaseException && error.code == 'unauthorized';
  }

  /// The window between "signed in" and "Firestore knows it".
  ///
  /// Distinguished from a real authorization failure: the credential is on its
  /// way, not refused. Worth waiting out rather than reporting.
  static bool isTransientAuthPropagation(Object error) {
    return error is FirebaseException && error.code == 'unauthenticated';
  }

  static bool isTransientFirestoreError(Object error) {
    // Plain Dart TimeoutExceptions (from the .timeout() wrappers used
    // throughout this class, e.g. _ensureAuthenticatedOwner's token
    // refresh) aren't FirebaseExceptions, so without this check a slow
    // network hop fell through to the generic "Impossible de mettre a
    // jour le profil" dead-end instead of the actionable "Connexion
    // instable" message.
    if (error is TimeoutException) {
      return true;
    }

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
      // Firestore reports 'unauthenticated' while the ID token has not
      // reached its client yet — routinely for a second or two after a fresh
      // sign-in, and reliably after the user clears app data and signs back
      // in. It matched none of the buckets here, so it fell through to the
      // generic "Chargement du profil impossible" dead end: no retry offered,
      // no explanation, on a session that was about to be perfectly valid.
      //
      // A genuinely signed-out user also produces this, and treating it as
      // transient costs nothing there: the auth state listener routes them to
      // login regardless of what this message says.
      case 'unauthenticated':
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

  /// [includePrivateFields] also fetches users/{uid}/private/contact
  /// (phone/birthDate/cvUrl) and merges it in. Only pass true for the
  /// signed-in owner's own uid or an admin session — the rules reject that
  /// read for anyone else, so requesting it for a third-party profile would
  /// just produce a noisy permission-denied for no reason.
  Future<AppUser?> fetchUser(
    String uid, {
    bool includePrivateFields = false,
  }) async {
    final doc = await _getWithRetry(_usersCollection.doc(uid));
    if (!doc.exists) {
      return null;
    }

    final data = doc.data();
    if (data == null) {
      return null;
    }

    final privateContact = includePrivateFields
        ? await _fetchPrivateContact(uid)
        : null;
    return AppUser.fromMap(data, privateContact: privateContact);
  }

  AppUser? _parseUserSafely(
    Map<String, dynamic> data, {
    Map<String, dynamic>? privateContact,
    required String source,
  }) {
    try {
      return AppUser.fromMap(data, privateContact: privateContact);
    } catch (error, stackTrace) {
      // Returning null here is what puts "Profil indisponible" on screen, and
      // `developer.log` never left the device — so the one place that knows
      // *why* the profile is unavailable said nothing that could be read
      // afterwards.
      AppLogger.warning(
        'profile unavailable; its document did not parse',
        source: 'profile/parse',
        error: error,
        stackTrace: stackTrace,
        metadata: <String, dynamic>{'origin': source},
      );
      return null;
    }
  }

  Stream<AppUser?> watchUser(String uid, {bool includePrivateFields = false}) {
    if (!includePrivateFields) {
      return _usersCollection.doc(uid).snapshots().map((snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          return null;
        }
        return _parseUserSafely(data, source: 'ProfileRepository.watchUser');
      });
    }

    return _watchUserWithPrivateContact(uid);
  }

  // phone/birthDate live in users/{uid}/private/contact (see
  // _privateContactKeys), a *subcollection* document. Firestore listeners on
  // the parent users/{uid} document never fire for a subcollection-only
  // write, so a single doc(uid).snapshots().asyncMap(...) — which only
  // re-fetches the private doc reactively when the parent doc itself also
  // changes — silently goes stale after a phone/birthDate-only edit. Listen
  // to both documents and re-emit a combined AppUser whenever either changes.
  Stream<AppUser?> _watchUserWithPrivateContact(String uid) {
    late final StreamController<AppUser?> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? userSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? contactSub;

    bool hasUserSnapshot = false;
    bool userExists = false;
    Map<String, dynamic>? userData;
    Map<String, dynamic>? privateContact;

    void emit() {
      if (!hasUserSnapshot) {
        return;
      }
      if (!userExists || userData == null) {
        controller.add(null);
        return;
      }
      controller.add(
        _parseUserSafely(
          userData!,
          privateContact: privateContact,
          source: 'ProfileRepository.watchUser',
        ),
      );
    }

    controller = StreamController<AppUser?>.broadcast(
      onListen: () {
        userSub = _usersCollection.doc(uid).snapshots().listen((snapshot) {
          hasUserSnapshot = true;
          userExists = snapshot.exists;
          userData = snapshot.data();
          emit();
        }, onError: controller.addError);
        contactSub = _privateContactDoc(uid).snapshots().listen((snapshot) {
          privateContact = snapshot.data();
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await userSub?.cancel();
        await contactSub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Supplementary contact fields, never a reason to fail the profile.
  ///
  /// `users/{uid}/private/contact` holds phone and birth date — extras shown
  /// on your own profile. This read used to propagate, so a hiccup on that
  /// one subdocument threw straight out of [fetchUser] and left the caller
  /// with no user at all: the whole screen collapsed to "Profil indisponible"
  /// over a phone number. Only [fetchUser] with `includePrivateFields` (i.e.
  /// your own profile) even reaches here, so the failure was invisible on
  /// everyone else's profile and hit exactly the owner.
  ///
  /// UserRepository's counterpart already swallowed this; the two are now
  /// consistent. Degrading to a profile without the private extras beats
  /// showing no profile.
  Future<Map<String, dynamic>?> _fetchPrivateContact(String uid) async {
    try {
      final doc = await _getWithRetry(_privateContactDoc(uid));
      return doc.data();
    } catch (error, stackTrace) {
      developer.log(
        'ProfileRepository private contact unavailable for $uid',
        name: 'ProfileRepository._fetchPrivateContact',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> saveUserProfile(AppUser updatedUser) async {
    final data = updatedUser.toMap();
    await _appendVerificationInvalidationIfCurrentProfileIsVerified(
      uid: updatedUser.uid,
      firestorePatch: data,
    );

    final privateContact = updatedUser.toPrivateContactMap();

    if (data.containsKey('profileVerificationInvalidatedAt')) {
      // The private/contact rule refuses phone/birthDate changes while the
      // profile is still verified, and can't see this parent-doc write's
      // pending value if both land in the same batch (see
      // contactOwnerProfileVerified() in firestore.rules). Commit the
      // invalidation first so the contact write below is evaluated against
      // an already-reset profile.
      await _usersCollection
          .doc(updatedUser.uid)
          .set(data, SetOptions(merge: true))
          .timeout(firestoreWriteTimeout);
      await _privateContactDoc(updatedUser.uid)
          .set(privateContact, SetOptions(merge: true))
          .timeout(firestoreWriteTimeout);
      return;
    }

    final batch = _firestore.batch()
      ..set(
        _usersCollection.doc(updatedUser.uid),
        data,
        SetOptions(merge: true),
      )
      ..set(
        _privateContactDoc(updatedUser.uid),
        privateContact,
        SetOptions(merge: true),
      );

    return batch.commit().timeout(firestoreWriteTimeout);
  }

  Future<ProfilePatchWriteResult> updateProfilePatch(
    String uid,
    Map<String, dynamic> patch,
  ) async {
    await _ensureAuthenticatedOwner(uid);

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

      // Source.server, not the default serverAndCache: this result decides
      // whether the profile is *currently* verified, which in turn decides
      // whether this write includes the verification-reset fields the
      // Firestore rule requires. A stale cached "not verified" read (silent
      // fallback on a flaky connection) would omit them while the rule
      // evaluates the real (verified) server state -- rejecting the whole
      // write with permission-denied even for an innocuous nom/bio edit.
      final doc = await _getWithRetry(
        _usersCollection.doc(uid),
        source: Source.server,
      );
      existingData = doc.data() ?? <String, dynamic>{};
      return existingData!;
    }

    final needsDeepMerge = firestorePatch.keys.any(
      _advancedProfileKeys.contains,
    );
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
        final merged = _deepMergeMap(
          old is Map ? Map<String, dynamic>.from(old) : <String, dynamic>{},
          Map<String, dynamic>.from(incomingLocal),
        );
        final cleaned = _pruneEmptyProfileMap(merged);
        firestorePatch.remove(key);
        if (cleaned.isEmpty) {
          firestorePatch[key] = FieldValue.delete();
          localPatch[key] = deleteField;
        } else {
          firestorePatch.addAll(
            _flattenAdvancedProfilePatch(
              profileKey: key,
              incoming: Map<String, dynamic>.from(incomingLocal),
              cleaned: cleaned,
            ),
          );
          localPatch[key] = cleaned;
        }
      }
    }

    if (firestorePatch.keys.any(_isTrustSensitivePatchKey)) {
      await _appendVerificationInvalidationIfCurrentProfileIsVerified(
        uid: uid,
        firestorePatch: firestorePatch,
        localPatch: localPatch,
        existingData: await loadExistingData(),
      );
    }

    final privatePatch = <String, dynamic>{};
    for (final key in _privateContactKeys) {
      if (firestorePatch.containsKey(key)) {
        privatePatch[key] = firestorePatch.remove(key);
      }
    }

    if (privatePatch.isNotEmpty &&
        firestorePatch.containsKey('profileVerificationInvalidatedAt')) {
      // See the matching comment in saveUserProfile(): the private/contact
      // rule can't observe this parent-doc write's pending value if both
      // land in the same batch, so commit the invalidation first.
      await _usersCollection
          .doc(uid)
          .update(firestorePatch)
          .timeout(firestoreWriteTimeout);
      await _privateContactDoc(uid)
          .set(privatePatch, SetOptions(merge: true))
          .timeout(firestoreWriteTimeout);
      return ProfilePatchWriteResult(appliedPatch: localPatch);
    }

    final batch = _firestore.batch();
    if (firestorePatch.isNotEmpty) {
      batch.update(_usersCollection.doc(uid), firestorePatch);
    }
    if (privatePatch.isNotEmpty) {
      batch.set(_privateContactDoc(uid), privatePatch, SetOptions(merge: true));
    }
    await batch.commit().timeout(firestoreWriteTimeout);

    return ProfilePatchWriteResult(appliedPatch: localPatch);
  }

  Future<String> updateProfilePhoto(String uid, String photoPath) async {
    await _ensureAuthenticatedOwner(uid);

    final ref = _storage.ref('profilePhotos/$uid');
    await ref
        .putFile(File(photoPath), SettableMetadata(contentType: 'image/jpeg'))
        .timeout(storageWriteTimeout);
    final url = await ref.getDownloadURL().timeout(firestoreReadTimeout);

    final patch = <String, dynamic>{'photoProfil': url};
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

  /// Loads a page of a profile's videos.
  ///
  /// [includeAllStates] must only be set when the signed-in user *is* [uid].
  /// It drops the `status == 'ready'` filter so authors can see their own
  /// videos while they are still being optimized or waiting on moderation.
  /// Without it the author gets the same view as a stranger: a video is
  /// invisible from the moment the upload finishes until an admin approves
  /// it, which reads as "my video was lost".
  ///
  /// This is not a privacy hole — `canReadVideo()` in firestore.rules already
  /// restricts non-`ready` documents to the owner and admin operators, so a
  /// caller passing this flag for somebody else's uid gets a
  /// permission-denied from the server rather than other people's drafts.
  Future<ProfileVideoPage> fetchUserVideos({
    required String uid,
    required int limit,
    ProfileVideoCursor? after,
    bool includeAllStates = false,
  }) async {
    Query<Map<String, dynamic>> query = _videosCollection.where(
      'uid',
      isEqualTo: uid,
    );

    if (!includeAllStates) {
      query = query.where('status', isEqualTo: 'ready');
    }

    query = query.orderBy('updatedAt', descending: true).limit(limit);

    if (after != null) {
      query = query.startAfterDocument(after.snapshot);
    }

    final snap = await query.get().timeout(firestoreReadTimeout);
    final videos = snap.docs
        .map(Video.fromDoc)
        // A video still being optimized has no playable URL yet — that is
        // precisely the state the owner needs to see, so only the public
        // view drops URL-less documents.
        .where((video) => includeAllStates || video.effectiveUrl.isNotEmpty)
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
    Stream<List<int>>? pdfReadStream,
    int? byteSize,
    String? previousCvUrl,
  }) async {
    await _ensureAuthenticatedOwner(uid);

    File? streamBackedFile;
    Reference? uploadedRef;

    try {
      Uint8List? uploadBytes = pdfBytes != null && pdfBytes.isNotEmpty
          ? Uint8List.fromList(pdfBytes)
          : null;
      File? uploadFile = pdfFile;

      if (uploadBytes != null) {
        _validatePdfBytes(uploadBytes);
      } else {
        if (uploadFile == null && pdfReadStream != null) {
          streamBackedFile = await _materializePdfStream(pdfReadStream);
          uploadFile = streamBackedFile;
        }

        if (uploadFile == null) {
          throw const CvUploadValidationException(
            'Le fichier CV est introuvable ou illisible.',
          );
        }

        await _validatePdfFile(uploadFile, knownSize: byteSize);
        uploadBytes = await uploadFile.readAsBytes();
        _validatePdfBytes(uploadBytes);
      }
      final bytesToUpload = uploadBytes;

      final targetFileName = _buildCvFileName();
      final storagePath = 'cvs/$uid/$targetFileName';
      final ref = _storage.ref(storagePath);
      final metadata = SettableMetadata(
        contentType: 'application/pdf',
        cacheControl: 'private, max-age=0, no-transform',
        customMetadata: <String, String>{'kind': 'player_cv', 'ownerUid': uid},
      );

      final uploadTask = await ref
          .putData(bytesToUpload, metadata)
          .timeout(storageWriteTimeout);
      uploadedRef = uploadTask.ref;

      late final String url;
      try {
        url = await uploadTask.ref.getDownloadURL().timeout(
          firestoreReadTimeout,
        );

        final patch = <String, dynamic>{'cvUrl': url};
        await _appendVerificationInvalidationIfCurrentProfileIsVerified(
          uid: uid,
          firestorePatch: patch,
        );

        await _usersCollection
            .doc(uid)
            .update(patch)
            .timeout(firestoreWriteTimeout);
      } catch (_) {
        await _deleteUploadedCvIfPresent(uploadedRef);
        rethrow;
      }

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
    } finally {
      if (streamBackedFile != null) {
        await _deleteTemporaryCvFile(streamBackedFile);
      }
    }
  }

  Future<void> deleteCv(String uid, {String? cvUrl}) async {
    await _ensureAuthenticatedOwner(uid);

    final patch = <String, dynamic>{'cvUrl': FieldValue.delete()};
    await _appendVerificationInvalidationIfCurrentProfileIsVerified(
      uid: uid,
      firestorePatch: patch,
    );

    await _usersCollection
        .doc(uid)
        .update(patch)
        .timeout(firestoreWriteTimeout);

    if (cvUrl != null && cvUrl.isNotEmpty) {
      try {
        await _storage.refFromURL(cvUrl).delete().timeout(storageWriteTimeout);
      } catch (cleanupError, cleanupStackTrace) {
        developer.log(
          'deleteCv storage cleanup warning',
          name: 'ProfileRepository.deleteCv',
          error: cleanupError,
          stackTrace: cleanupStackTrace,
        );
      }
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getWithRetry(
    DocumentReference<Map<String, dynamic>> ref, {
    Source source = Source.serverAndCache,
  }) async {
    int attempt = 0;
    while (attempt < 3) {
      try {
        return await ref
            .get(GetOptions(source: source))
            .timeout(firestoreReadTimeout);
      } catch (error) {
        attempt++;
        if (attempt >= 3) {
          rethrow;
        }
        // A pending ID token needs real time, not a token gesture: 300ms and
        // 600ms both land well before Firestore has one, so all three
        // attempts failed on the same missing credential and the caller saw a
        // hard error for a session that became valid a second later.
        final backoff = isTransientAuthPropagation(error)
            ? Duration(milliseconds: 900 * attempt)
            : Duration(milliseconds: 300 * attempt);
        await Future.delayed(backoff);
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
    // Source.server for the same reason as loadExistingData() in
    // updateProfilePatch: this decides whether the verification-reset
    // fields are included, and a stale cached read can disagree with what
    // the Firestore rule sees, turning an ordinary photo/CV/profile write
    // into a permission-denied.
    final data =
        existingData ??
        (await _getWithRetry(
          _usersCollection.doc(uid),
          source: Source.server,
        )).data() ??
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
    final status = data['profileVerificationStatus']
        ?.toString()
        .trim()
        .toLowerCase();
    return data['profileVerified'] == true || status == 'verified';
  }

  static String _buildCvFileName() {
    return 'cv_${DateTime.now().millisecondsSinceEpoch}.pdf';
  }

  static bool _hasPdfHeader(List<int> bytes) {
    if (bytes.length < _pdfHeader.length) {
      return false;
    }

    for (var i = 0; i < _pdfHeader.length; i++) {
      if (bytes[i] != _pdfHeader[i]) {
        return false;
      }
    }
    return true;
  }

  static void _validatePdfBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const CvUploadValidationException('Le fichier CV est vide.');
    }
    if (bytes.length > maxCvPdfBytes) {
      throw const CvUploadValidationException('Le CV doit faire 5 Mo maximum.');
    }
    if (!_hasPdfHeader(bytes)) {
      throw const CvUploadValidationException('Le CV doit etre un PDF valide.');
    }
  }

  static Future<void> _validatePdfFile(File file, {int? knownSize}) async {
    final exists = await file.exists();
    if (!exists) {
      throw const CvUploadValidationException(
        'Le fichier CV est introuvable ou illisible.',
      );
    }

    final measuredSize = await file.length();
    final size = measuredSize > 0 ? measuredSize : knownSize ?? 0;
    if (size <= 0) {
      throw const CvUploadValidationException('Le fichier CV est vide.');
    }
    if (size > maxCvPdfBytes) {
      throw const CvUploadValidationException('Le CV doit faire 5 Mo maximum.');
    }

    final headerLength = size < _pdfHeader.length ? size : _pdfHeader.length;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, headerLength)) {
      builder.add(chunk);
    }
    if (!_hasPdfHeader(builder.takeBytes())) {
      throw const CvUploadValidationException('Le CV doit etre un PDF valide.');
    }
  }

  static Future<File> _materializePdfStream(Stream<List<int>> stream) async {
    final tempDir = await Directory.systemTemp.createTemp('adfoot_cv_');
    final tempFile = File('${tempDir.path}/cv.pdf');
    final sink = tempFile.openWrite();
    var sinkClosed = false;
    var byteCount = 0;

    try {
      await for (final chunk in stream) {
        if (chunk.isEmpty) {
          continue;
        }
        byteCount += chunk.length;
        if (byteCount > maxCvPdfBytes) {
          throw const CvUploadValidationException(
            'Le CV doit faire 5 Mo maximum.',
          );
        }
        sink.add(chunk);
      }
      await sink.close();
      sinkClosed = true;
      await _validatePdfFile(tempFile, knownSize: byteCount);
      return tempFile;
    } catch (_) {
      if (!sinkClosed) {
        await sink.close();
      }
      await _deleteTemporaryCvFile(tempFile);
      rethrow;
    }
  }

  static Future<void> _deleteTemporaryCvFile(File file) async {
    try {
      final directory = file.parent;
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (cleanupError, cleanupStackTrace) {
      developer.log(
        'temporary CV cleanup warning',
        name: 'ProfileRepository.uploadCvPdf',
        error: cleanupError,
        stackTrace: cleanupStackTrace,
      );
    }
  }

  static Future<void> _deleteUploadedCvIfPresent(Reference? ref) async {
    if (ref == null) {
      return;
    }

    try {
      await ref.delete().timeout(storageWriteTimeout);
    } catch (cleanupError, cleanupStackTrace) {
      developer.log(
        'uploaded CV cleanup warning',
        name: 'ProfileRepository.uploadCvPdf',
        error: cleanupError,
        stackTrace: cleanupStackTrace,
      );
    }
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
        final mapped = _advancedProfileKeys.contains(key)
            ? _sanitizeAdvancedProfileMap(value)
            : Map<String, dynamic>.from(value);
        if (mapped.isEmpty) {
          return;
        }
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

  static Map<String, dynamic> _sanitizeAdvancedProfileMap(Map value) {
    final mapped = <String, dynamic>{};

    value.forEach((rawKey, rawValue) {
      final key = rawKey.toString().trim();
      if (key.isEmpty) {
        return;
      }

      final sanitized = _sanitizeAdvancedProfileValue(rawValue);
      mapped[key] = sanitized;
    });

    return mapped;
  }

  static dynamic _sanitizeAdvancedProfileValue(dynamic value) {
    if (value == null || value is ProfileFieldDelete || value is FieldValue) {
      return _deleteNestedProfileField;
    }

    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? _deleteNestedProfileField : trimmed;
    }

    if (value is Map) {
      final mapped = _sanitizeAdvancedProfileMap(value);
      return mapped.isEmpty ? _deleteNestedProfileField : mapped;
    }

    if (value is List) {
      final sanitizedItems = <dynamic>[];
      for (final item in value) {
        final sanitized = _sanitizeAdvancedProfileValue(item);
        if (sanitized is _ProfileNestedFieldDelete) {
          continue;
        }
        // A Map nested inside a List can't carry the delete sentinel: Firestore
        // has no concept of "delete this field of this array element", only
        // whole-array-field deletes. Drop the sentinel-valued keys instead so
        // the sentinel object never reaches the Firestore write.
        if (sanitized is Map) {
          final cleanedItem = <String, dynamic>{};
          sanitized.forEach((key, itemValue) {
            if (itemValue is _ProfileNestedFieldDelete) {
              return;
            }
            cleanedItem[key.toString()] = itemValue;
          });
          if (cleanedItem.isEmpty) {
            continue;
          }
          sanitizedItems.add(cleanedItem);
          continue;
        }
        sanitizedItems.add(sanitized);
      }
      return sanitizedItems.isEmpty
          ? _deleteNestedProfileField
          : sanitizedItems;
    }

    return value;
  }

  static Map<String, dynamic> _deepMergeMap(
    Map<String, dynamic> base,
    Map<String, dynamic> incoming,
  ) {
    final result = Map<String, dynamic>.from(base);

    incoming.forEach((key, value) {
      if (value == null || value is _ProfileNestedFieldDelete) {
        result.remove(key);
        return;
      }
      final old = result[key];
      if (old is Map && value is Map) {
        final merged = _deepMergeMap(
          Map<String, dynamic>.from(old),
          Map<String, dynamic>.from(value),
        );
        if (_isEmptyProfileValue(merged)) {
          result.remove(key);
        } else {
          result[key] = merged;
        }
      } else if (_isEmptyProfileValue(value)) {
        result.remove(key);
      } else {
        result[key] = value;
      }
    });

    return result;
  }

  static Map<String, dynamic> _pruneEmptyProfileMap(
    Map<String, dynamic> value,
  ) {
    final pruned = <String, dynamic>{};

    value.forEach((key, rawValue) {
      if (rawValue is Map) {
        final nested = _pruneEmptyProfileMap(
          Map<String, dynamic>.from(rawValue),
        );
        if (nested.isNotEmpty) {
          pruned[key] = nested;
        }
        return;
      }

      if (!_isEmptyProfileValue(rawValue)) {
        pruned[key] = rawValue;
      }
    });

    return pruned;
  }

  static Map<String, dynamic> _flattenAdvancedProfilePatch({
    required String profileKey,
    required Map<String, dynamic> incoming,
    required Map<String, dynamic> cleaned,
  }) {
    final patch = <String, dynamic>{};

    void visit(String path, dynamic value, dynamic cleanedValue) {
      if (value == null || value is _ProfileNestedFieldDelete) {
        patch[path] = FieldValue.delete();
        return;
      }

      if (value is Map) {
        if (cleanedValue is! Map || cleanedValue.isEmpty) {
          patch[path] = FieldValue.delete();
          return;
        }

        final cleanedMap = Map<String, dynamic>.from(cleanedValue);
        value.forEach((rawKey, rawValue) {
          final key = rawKey.toString().trim();
          if (key.isEmpty) {
            return;
          }
          visit('$path.$key', rawValue, cleanedMap[key]);
        });
        return;
      }

      if (value is List) {
        // Defense in depth: strip any residual delete sentinel before this
        // list ever reaches Firestore.update(), even though the sanitize
        // step above should already have removed them.
        final sanitizedList = _stripListSentinels(value);
        if (sanitizedList.isEmpty) {
          patch[path] = FieldValue.delete();
          return;
        }
        patch[path] = sanitizedList;
        return;
      }

      if (_isEmptyProfileValue(value)) {
        patch[path] = FieldValue.delete();
        return;
      }

      patch[path] = value;
    }

    incoming.forEach((key, value) {
      visit('$profileKey.$key', value, cleaned[key]);
    });

    return patch;
  }

  static List<dynamic> _stripListSentinels(List<dynamic> value) {
    final cleaned = <dynamic>[];
    for (final item in value) {
      if (item is _ProfileNestedFieldDelete) {
        continue;
      }
      if (item is Map) {
        final cleanedItem = <String, dynamic>{};
        item.forEach((key, itemValue) {
          if (itemValue is _ProfileNestedFieldDelete) {
            return;
          }
          cleanedItem[key.toString()] = itemValue is List
              ? _stripListSentinels(itemValue)
              : itemValue;
        });
        if (cleanedItem.isNotEmpty) {
          cleaned.add(cleanedItem);
        }
        continue;
      }
      if (item is List) {
        final nested = _stripListSentinels(item);
        if (nested.isNotEmpty) {
          cleaned.add(nested);
        }
        continue;
      }
      cleaned.add(item);
    }
    return cleaned;
  }

  static bool _isEmptyProfileValue(dynamic value) {
    if (value == null || value is _ProfileNestedFieldDelete) {
      return true;
    }
    if (value is String) {
      return value.trim().isEmpty;
    }
    // A Map/List is only *meaningfully* empty once every value inside it is
    // itself empty/a delete sentinel — a map with 3 keys where only one
    // holds real data (the rest were left blank in the form) is not empty,
    // even though its key count is non-zero. Keeping this in sync with
    // _pruneEmptyProfileMap's notion of "empty" avoids _deepMergeMap treating
    // an all-blank nested block as real data to preserve.
    if (value is Map) {
      return value.isEmpty || value.values.every(_isEmptyProfileValue);
    }
    if (value is List) {
      return value.isEmpty || value.every(_isEmptyProfileValue);
    }
    return false;
  }

  static bool _isTrustSensitivePatchKey(String key) {
    if (_trustSensitiveProfileKeys.contains(key)) {
      return true;
    }
    return _advancedProfileKeys.any(
      (profileKey) => key.startsWith('$profileKey.'),
    );
  }
}
