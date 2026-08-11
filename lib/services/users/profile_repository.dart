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
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storageOverride = storage,
       _authOverride = auth;

  static const ProfileFieldDelete deleteField = ProfileFieldDelete._();
  static const Duration firestoreReadTimeout = Duration(seconds: 12);
  static const Duration firestoreWriteTimeout = Duration(seconds: 15);
  static const Duration storageWriteTimeout = Duration(seconds: 45);
  static const Duration authRefreshTimeout = Duration(seconds: 8);
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

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _videosCollection =>
      _firestore.collection('videos');

  DocumentReference<Map<String, dynamic>> _privateContactDoc(String uid) =>
      _usersCollection.doc(uid).collection('private').doc('contact');

  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  String? get currentAuthUid => _auth.currentUser?.uid;

  Future<void> _ensureAuthenticatedOwner(String uid) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != uid) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'permission-denied',
        message: 'Authenticated profile owner required.',
      );
    }

    try {
      await currentUser.getIdToken(true).timeout(authRefreshTimeout);
    } on TimeoutException {
      await currentUser.getIdToken().timeout(authRefreshTimeout);
    } on FirebaseException catch (error) {
      if (!_isTransientAuthTokenRefreshError(error)) {
        rethrow;
      }
      await currentUser.getIdToken().timeout(authRefreshTimeout);
    }
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
      developer.log(
        'user document parse error',
        name: source,
        error: error,
        stackTrace: stackTrace,
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

    return _usersCollection.doc(uid).snapshots().asyncMap((snapshot) async {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return null;
      }
      final privateContact = await _fetchPrivateContact(uid);
      return _parseUserSafely(
        data,
        privateContact: privateContact,
        source: 'ProfileRepository.watchUser',
      );
    });
  }

  Future<Map<String, dynamic>?> _fetchPrivateContact(String uid) async {
    final doc = await _getWithRetry(_privateContactDoc(uid));
    return doc.data();
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

      final doc = await _getWithRetry(_usersCollection.doc(uid));
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
        .where((video) => video.effectiveUrl.isNotEmpty)
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
    final data =
        existingData ??
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

  static bool _isEmptyProfileValue(dynamic value) {
    if (value == null || value is _ProfileNestedFieldDelete) {
      return true;
    }
    if (value is String) {
      return value.trim().isEmpty;
    }
    if (value is Map) {
      return value.isEmpty;
    }
    if (value is List) {
      return value.isEmpty;
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
