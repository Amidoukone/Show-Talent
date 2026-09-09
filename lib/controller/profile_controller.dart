import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/services/users/profile_repository.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/videos/video_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get/get.dart';
import 'package:adfoot/services/app_logger.dart';

class ProfileAccessRevokedException implements Exception {
  const ProfileAccessRevokedException({this.title, this.message});

  final String? title;
  final String? message;

  @override
  String toString() {
    final resolvedMessage = message;
    if (resolvedMessage == null || resolvedMessage.trim().isEmpty) {
      return 'ProfileAccessRevokedException';
    }
    return resolvedMessage;
  }
}

class ProfileLoadException implements Exception {
  const ProfileLoadException(this.message);

  final String message;
}

class ProfileController extends GetxController {
  static const ProfileFieldDelete deleteField = ProfileRepository.deleteField;
  static const int maxCvPdfBytes = ProfileRepository.maxCvPdfBytes;
  static const Duration _userRefreshTimeout = Duration(seconds: 8);
  static const Duration _profileLoadTimeout = Duration(seconds: 25);

  ProfileController({ProfileRepository? profileRepository})
    : _profileRepository = profileRepository ?? ProfileRepository();

  final ProfileRepository _profileRepository;
  final VideoManager _videoManager = VideoManager();

  /// True when [uid] is the signed-in user, i.e. this profile's videos may be
  /// listed in every lifecycle state rather than only the public `ready` ones.
  ///
  /// Reads the uid off the repository, like every other auth check in this
  /// controller. Injecting an AuthSessionService for it instead would build a
  /// FirebaseAuth *and* a FirebaseFunctions client eagerly in the
  /// constructor, which makes ProfileController unconstructible wherever
  /// Firebase has not been initialized.
  bool isOwnProfile(String uid) {
    final currentUid = _profileRepository.currentAuthUid;
    return currentUid != null && currentUid.isNotEmpty && currentUid == uid;
  }

  AppUser? user;
  StreamSubscription<AppUser?>? _userSubscription;

  final isLoadingPhoto = false.obs;
  final videoList = <Video>[].obs;
  bool isLoadingUser = false;
  String? profileLoadErrorTitle;
  String? profileLoadErrorMessage;
  String? lastProfileWriteErrorTitle;
  String? lastProfileWriteErrorMessage;
  String? lastCvUploadErrorTitle;
  String? lastCvUploadErrorMessage;

  ProfileVideoCursor? _lastVideoCursor;
  static const int _videoFetchLimit = 20;
  static const int _videoMemoryLimit = 25;

  bool _hasMoreVideos = true;
  bool _isLoadingVideos = false;
  Completer<void>? _loadingCompleter;
  int _profileLoadSerial = 0;

  bool get hasMoreVideos => _hasMoreVideos;
  bool get isLoadingVideos => _isLoadingVideos;

  bool _isPermissionDenied(Object error) =>
      ProfileRepository.isPermissionDenied(error);

  bool _isAccessDenied(Object error) =>
      _isPermissionDenied(error) || ProfileRepository.isUnauthorized(error);

  bool _isTransientFirestoreError(Object error) =>
      ProfileRepository.isTransientFirestoreError(error);

  String _firebaseFailureCode(Object error) {
    if (error is FirebaseException) {
      return '${error.plugin}/${error.code}';
    }
    return error.runtimeType.toString();
  }

  void _clearProfileWriteError() {
    lastProfileWriteErrorTitle = null;
    lastProfileWriteErrorMessage = null;
  }

  void _setProfileWriteError(String title, String message) {
    lastProfileWriteErrorTitle = title;
    lastProfileWriteErrorMessage = message;
  }

  void _clearCvUploadError() {
    lastCvUploadErrorTitle = null;
    lastCvUploadErrorMessage = null;
  }

  void _setCvUploadError(String title, String message) {
    lastCvUploadErrorTitle = title;
    lastCvUploadErrorMessage = message;
  }

  String? _ownerSessionProblemMessage(String uid) {
    final authUid = _profileRepository.currentAuthUid;
    if (authUid == null) {
      return 'profileFirebaseSessionExpiredMessage'.tr;
    }
    if (authUid != uid) {
      return 'profileSessionMismatchMessage'.tr;
    }
    return null;
  }

  String _profileWriteAccessDeniedMessage(Object error, String uid) {
    final code = _firebaseFailureCode(error);
    final ownerProblem = _ownerSessionProblemMessage(uid);
    if (ownerProblem != null) {
      return '$ownerProblem Code: $code';
    }

    if (ProfileRepository.isUnauthorized(error)) {
      return 'profileWriteAppCheckDeniedMessage'.trParams({'code': code});
    }

    return 'profileWriteGenericDeniedMessage'.trParams({'code': code});
  }

  String _cvAccessDeniedMessage(Object error, String uid) {
    final code = _firebaseFailureCode(error);
    final ownerProblem = _ownerSessionProblemMessage(uid);
    if (ownerProblem != null) {
      return '$ownerProblem Code: $code';
    }

    if (ProfileRepository.isUnauthorized(error)) {
      return 'profileCvStorageAppCheckDeniedMessage'.trParams({'code': code});
    }

    return 'profileCvStorageGenericDeniedMessage'.trParams({'code': code});
  }

  String _profileLoadErrorMessage(Object error) {
    if (error is ProfileLoadException) {
      return error.message;
    }

    if (_isPermissionDenied(error)) {
      return 'profileNoAccessCurrentSessionMessage'.tr;
    }

    if (_isTransientFirestoreError(error)) {
      return 'profileLoadConnectionUnstableMessage'.tr;
    }

    return 'profileLoadUnavailableMessage'.tr;
  }

  String _profileWriteFailureMessage(Object error) {
    if (_isTransientFirestoreError(error)) {
      return 'profileLoadConnectionUnstableMessage'.tr;
    }

    return 'profileWriteUnavailableMessage'.tr;
  }

  String _profilePhotoFailureMessage(Object error) {
    if (error is FirebaseException && error.plugin == 'firebase_app_check') {
      return 'profileSecureConnectionUnavailableMessage'.tr;
    }

    if (_isTransientFirestoreError(error)) {
      return 'profileLoadConnectionUnstableMessage'.tr;
    }

    return 'profilePhotoUpdateUnavailableMessage'.tr;
  }

  Future<void> _handleProtectedAccessDenied() async {
    if (!Get.isRegistered<UserController>()) {
      return;
    }

    await Get.find<UserController>().handleProtectedAccessDenied(
      fallbackTitle: VideoUiStrings.protectedAccessTitle,
      fallbackMessage: VideoUiStrings.protectedAccessMessage,
    );
  }

  @override
  void onClose() async {
    final ctx = 'profile:${user?.uid ?? ''}';
    await _videoManager.disposeAllForContext(ctx);
    await _userSubscription?.cancel();
    super.onClose();
  }

  Future<void> _safeRefreshCurrentUser() async {
    if (!Get.isRegistered<UserController>()) {
      return;
    }

    try {
      await Get.find<UserController>().refreshUser().timeout(
        _userRefreshTimeout,
      );
    } catch (refreshError, refreshStackTrace) {
      AppLogger.warning(
        'ProfileController refreshUser warning: '
        '$refreshError\n$refreshStackTrace',
        source: 'ProfileController._safeRefreshCurrentUser',
        error: refreshError,
        stackTrace: refreshStackTrace,
      );
    }
  }

  /// True once a profile load attempt has settled for this controller.
  ///
  /// Lets the screen tell "still loading" apart from "loaded nothing", so a
  /// `user == null` state can never render as a spinner with no attempt
  /// behind it and nothing left to complete it.
  bool hasAttemptedProfileLoad = false;

  Future<void> updateUserId(String uid) async {
    // Reused from FeatureControllerRegistry's grace period: the screen for
    // this uid was released and reclaimed before the controller was torn
    // down, so this is the same instance that already loaded this profile
    // -- its Firestore listener (_startUserListener) never stopped, so
    // what's already in [user]/[videoList] is still current, not stale.
    // Skipping the refetch is what makes returning to a just-left profile
    // instant instead of paying for a second full network round trip.
    //
    // The two other call sites of this method (profile_screen.dart's
    // self-heal re-arm and its Réessayer button) never hit this: the first
    // only fires while `hasAttemptedProfileLoad` is still false, the second
    // only shows once a load attempt failed to produce a `user` -- both
    // leave the guard below false, so a real fetch still runs. Pull-to-
    // refresh goes through refreshProfileVideos() instead, which this does
    // not touch at all.
    if (user?.uid == uid && hasAttemptedProfileLoad) {
      return;
    }

    final requestSerial = ++_profileLoadSerial;
    isLoadingUser = true;
    profileLoadErrorTitle = null;
    profileLoadErrorMessage = null;
    if (user?.uid != uid) {
      user = null;
      videoList.clear();
      _lastVideoCursor = null;
      _hasMoreVideos = true;
    }
    update();

    try {
      // Started alongside the user-doc fetch, not after it: fetchUserVideos
      // only ever needs `uid` (see isOwnProfile, which reads the signed-in
      // uid, never `user`'s content), so the two reads have no data
      // dependency and don't need to be sequential. fetchUserVideos never
      // rethrows (it reports its own failures internally), so starting it
      // here cannot turn into an unhandled error if the user fetch below
      // fails instead.
      final videosFuture = fetchUserVideos(uid, isRefresh: true);

      final fetchedUser = await _profileRepository
          .fetchUser(
            uid,
            includePrivateFields: uid == _profileRepository.currentAuthUid,
          )
          .timeout(_profileLoadTimeout);
      if (requestSerial != _profileLoadSerial) {
        return;
      }
      if (fetchedUser == null) {
        throw ProfileLoadException('profileNotFoundMessage'.tr);
      }

      user = fetchedUser;
      isLoadingUser = false;
      hasAttemptedProfileLoad = true;
      update();

      _startUserListener(uid);
      await videosFuture;
    } catch (e, st) {
      if (requestSerial != _profileLoadSerial) {
        return;
      }
      AppLogger.warning(
        'updateUserId error: $e\n$st',
        source: 'ProfileController.updateUserId',
        error: e,
        stackTrace: st,
      );
      isLoadingUser = false;
      hasAttemptedProfileLoad = true;
      profileLoadErrorTitle = 'profileUnavailableTitle'.tr;
      profileLoadErrorMessage = _profileLoadErrorMessage(e);
      update();
      if (_isPermissionDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
        return;
      }
      AdFeedback.error(
        'profileUnavailableTitle'.tr,
        'profileLoadUnavailableShortMessage'.tr,
      );
    } finally {
      // Guarantees the screen can always leave its loading state: a settled
      // attempt that produced neither a profile nor an error message would
      // otherwise render as a spinner nothing will ever replace.
      if (requestSerial == _profileLoadSerial) {
        isLoadingUser = false;
        hasAttemptedProfileLoad = true;
        if (user == null &&
            (profileLoadErrorMessage == null ||
                profileLoadErrorMessage!.trim().isEmpty)) {
          profileLoadErrorTitle = 'profileUnavailableTitle'.tr;
          profileLoadErrorMessage = 'profileLoadUnavailableMessage'.tr;
        }
        update();
      }
    }
  }

  void _startUserListener(String uid) {
    _userSubscription?.cancel();
    _userSubscription = _profileRepository
        .watchUser(
          uid,
          includePrivateFields: uid == _profileRepository.currentAuthUid,
        )
        .listen(
          (updatedUser) {
            if (updatedUser == null) {
              return;
            }
            user = updatedUser;
            update();
          },
          onError: (error, stackTrace) {
            AppLogger.debug('profile user listener error: $error\n$stackTrace');
            if (user == null) {
              profileLoadErrorTitle = 'profileUnavailableTitle'.tr;
              profileLoadErrorMessage = _profileLoadErrorMessage(error);
              update();
            }
            if (_isPermissionDenied(error)) {
              unawaited(_handleProtectedAccessDenied());
            }
          },
        );
  }

  Future<void> updateUserProfile(AppUser updatedUser) async {
    try {
      await _profileRepository.saveUserProfile(updatedUser);

      try {
        user = updatedUser;
        update();
      } catch (localSyncError, localSyncStackTrace) {
        AppLogger.warning(
          'updateUserProfile local sync warning: '
          '$localSyncError\n$localSyncStackTrace',
          source: 'ProfileController.updateUserProfile',
          error: localSyncError,
          stackTrace: localSyncStackTrace,
        );
      }

      await _safeRefreshCurrentUser();
    } catch (e, st) {
      AppLogger.warning(
        'updateUserProfile error: $e\n$st',
        source: 'ProfileController.updateUserProfile',
        error: e,
        stackTrace: st,
      );
      if (_isAccessDenied(e)) {
        AdFeedback.error(
          'profilePermissionDeniedTitle'.tr,
          'profilePhotoPermissionDeniedMessage'.tr,
        );
        unawaited(_handleProtectedAccessDenied());
        throw const ProfileAccessRevokedException();
      }
      final message = _profileWriteFailureMessage(e);
      AdFeedback.error('profileUpdateFailedTitle'.tr, message);
      rethrow;
    }
  }

  Future<void> updateProfilePatch(
    String uid,
    Map<String, dynamic> patch, {
    bool refreshGlobalUser = true,
    bool alsoUpdateLocalUser = true,
  }) async {
    try {
      _clearProfileWriteError();
      if (patch.isEmpty) {
        return;
      }
      final ownerProblem = _ownerSessionProblemMessage(uid);
      if (ownerProblem != null) {
        final sessionInvalidTitle = 'profileInvalidSessionTitle'.tr;
        _setProfileWriteError(sessionInvalidTitle, ownerProblem);
        AdFeedback.error(sessionInvalidTitle, ownerProblem);
        unawaited(_handleProtectedAccessDenied());
        throw ProfileAccessRevokedException(
          title: sessionInvalidTitle,
          message: ownerProblem,
        );
      }

      final writeResult = await _profileRepository.updateProfilePatch(
        uid,
        patch,
      );
      final finalPatch = writeResult.appliedPatch;
      if (finalPatch.isEmpty) {
        return;
      }

      if (alsoUpdateLocalUser && user != null && user!.uid == uid) {
        try {
          _applyPatchToLocalUser(finalPatch);
          update();
        } catch (localSyncError, localSyncStackTrace) {
          AppLogger.warning(
            'updateProfilePatch local sync warning: '
            '$localSyncError\n$localSyncStackTrace\n'
            'patch=$finalPatch',
            source: 'ProfileController.updateProfilePatch',
            error: localSyncError,
            stackTrace: localSyncStackTrace,
          );
        }
      }

      if (refreshGlobalUser && Get.isRegistered<UserController>()) {
        await _safeRefreshCurrentUser();
      }
    } catch (e, st) {
      AppLogger.warning(
        'updateProfilePatch error: $e\n$st',
        source: 'ProfileController.updateProfilePatch',
        error: e,
        stackTrace: st,
      );
      if (_isAccessDenied(e)) {
        final message = _profileWriteAccessDeniedMessage(e, uid);
        final accessDeniedTitle = 'accessDeniedTitle'.tr;
        _setProfileWriteError(accessDeniedTitle, message);
        AppLogger.error(
          'Profile write rejected',
          source: 'ProfileController.updateProfilePatch',
          error: e,
          stackTrace: st,
          metadata: {
            'code': _firebaseFailureCode(e),
            'uidMatchesAuth': _profileRepository.currentAuthUid == uid,
            'patchKeys': patch.keys.join(','),
            'role': user?.role,
          },
        );
        AdFeedback.error(
          accessDeniedTitle,
          message,
          duration: const Duration(seconds: 6),
        );
        unawaited(_handleProtectedAccessDenied());
        throw ProfileAccessRevokedException(
          title: accessDeniedTitle,
          message: message,
        );
      }
      final message = _profileWriteFailureMessage(e);
      final updateFailedTitle = 'profileUpdateFailedTitle'.tr;
      _setProfileWriteError(updateFailedTitle, message);
      AppLogger.error(
        'Profile write failed',
        source: 'ProfileController.updateProfilePatch',
        error: e,
        stackTrace: st,
        metadata: {
          'code': _firebaseFailureCode(e),
          'uidMatchesAuth': _profileRepository.currentAuthUid == uid,
          'patchKeys': patch.keys.join(','),
          'role': user?.role,
        },
      );
      AdFeedback.error(
        updateFailedTitle,
        message,
        duration: const Duration(seconds: 6),
      );
      rethrow;
    }
  }

  void _applyPatchToLocalUser(Map<String, dynamic> patch) {
    final u = user;
    if (u == null) {
      return;
    }

    if (patch.containsKey('nom')) {
      u.nom = patch['nom'] as String;
    }
    if (patch.containsKey('photoProfil')) {
      final value = patch['photoProfil'];
      if (value is! ProfileFieldDelete) {
        u.photoProfil = value as String;
      }
    }

    void applyNullableString(String key, void Function(String?) setter) {
      if (!patch.containsKey(key)) {
        return;
      }
      final value = patch[key];
      if (value is ProfileFieldDelete) {
        setter(null);
      } else {
        setter(value as String?);
      }
    }

    void applyNullableInt(String key, void Function(int?) setter) {
      if (!patch.containsKey(key)) {
        return;
      }
      final value = patch[key];
      if (value is ProfileFieldDelete) {
        setter(null);
        return;
      }
      if (value is num) {
        setter(value.toInt());
        return;
      }
      setter(value as int?);
    }

    applyNullableString('phone', (v) => u.phone = v);
    applyNullableString('bio', (v) => u.bio = v);
    applyNullableString('position', (v) => u.position = v);
    applyNullableString('team', (v) => u.team = v);
    applyNullableString('clubActuel', (v) => u.clubActuel = v);
    applyNullableString('nomClub', (v) => u.nomClub = v);
    applyNullableString('ligue', (v) => u.ligue = v);
    applyNullableString('entreprise', (v) => u.entreprise = v);
    applyNullableString('country', (v) => u.country = v);
    applyNullableString('city', (v) => u.city = v);
    applyNullableString('region', (v) => u.region = v);

    applyNullableInt('nombreDeMatchs', (v) => u.nombreDeMatchs = v);
    applyNullableInt('buts', (v) => u.buts = v);
    applyNullableInt('assistances', (v) => u.assistances = v);
    applyNullableInt('nombreDeRecrutements', (v) => u.nombreDeRecrutements = v);

    if (patch.containsKey('performances')) {
      final value = patch['performances'];
      if (value is ProfileFieldDelete) {
        u.performances = null;
      } else if (value is Map) {
        u.performances = Map<String, double>.from(
          value.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
        );
      }
    }

    if (patch.containsKey('cvUrl')) {
      final value = patch['cvUrl'];
      if (value is ProfileFieldDelete) {
        u.cvUrl = null;
      } else {
        u.cvUrl = value as String?;
      }
    }

    if (patch.containsKey('birthDate')) {
      final value = patch['birthDate'];
      if (value is ProfileFieldDelete) {
        u.birthDate = null;
      } else if (value is DateTime) {
        u.birthDate = value;
      }
    }

    if (patch.containsKey('languages')) {
      final value = patch['languages'];
      if (value is ProfileFieldDelete) {
        u.languages = null;
      } else if (value is List) {
        u.languages = value.map((e) => e.toString()).toList();
      }
    }

    if (patch.containsKey('openToOpportunities')) {
      u.openToOpportunities = patch['openToOpportunities'] as bool?;
    }
    if (patch.containsKey('profilePublic')) {
      u.profilePublic = patch['profilePublic'] as bool;
    }
    if (patch.containsKey('allowMessages')) {
      u.allowMessages = patch['allowMessages'] as bool;
    }
    if (patch.containsKey('profileVerified')) {
      u.profileVerified = patch['profileVerified'] == true;
    }
    if (patch.containsKey('profileVerificationStatus')) {
      u.profileVerificationStatus =
          patch['profileVerificationStatus']?.toString() ?? 'unverified';
    }
    if (patch.containsKey('profileVerificationUpdatedAt')) {
      final value = patch['profileVerificationUpdatedAt'];
      if (value is DateTime) {
        u.profileVerificationUpdatedAt = value;
      }
    }
    applyNullableString(
      'profileVerificationUpdatedBy',
      (v) => u.profileVerificationUpdatedBy = v,
    );
    if (patch.containsKey('profileVerificationInvalidatedAt')) {
      final value = patch['profileVerificationInvalidatedAt'];
      if (value is DateTime) {
        u.profileVerificationInvalidatedAt = value;
      }
    }
    applyNullableString(
      'profileVerificationInvalidatedBy',
      (v) => u.profileVerificationInvalidatedBy = v,
    );
    applyNullableString(
      'profileVerificationInvalidationReason',
      (v) => u.profileVerificationInvalidationReason = v,
    );

    void applyMap(String key, void Function(Map<String, dynamic>) setter) {
      if (!patch.containsKey(key)) {
        return;
      }
      final value = patch[key];
      if (value is ProfileFieldDelete) {
        setter(<String, dynamic>{});
        return;
      }
      if (value is Map) {
        setter(Map<String, dynamic>.from(value));
      }
    }

    applyMap('playerProfile', (m) => u.playerProfile = m);
    applyMap('clubProfile', (m) => u.clubProfile = m);
    applyMap('agentProfile', (m) => u.agentProfile = m);
  }

  Future<void> updateProfilePhoto(String uid, String photoPath) async {
    isLoadingPhoto.value = true;
    try {
      final url = await _profileRepository.updateProfilePhoto(uid, photoPath);

      user?.photoProfil = url;
      update();

      await _safeRefreshCurrentUser();

      AdFeedback.success(
        'profilePhotoUpdatedTitle'.tr,
        'profilePhotoUpdatedMessage'.tr,
      );
    } catch (e, st) {
      AppLogger.warning(
        'updateProfilePhoto error: $e\n$st',
        source: 'ProfileController.updateProfilePhoto',
        error: e,
        stackTrace: st,
      );
      if (_isAccessDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
        throw const ProfileAccessRevokedException();
      }
      AdFeedback.error(
        'profilePhotoUpdateFailedTitle'.tr,
        _profilePhotoFailureMessage(e),
      );
    } finally {
      isLoadingPhoto.value = false;
    }
  }

  /// Drops videos this profile still lists but that no longer exist.
  ///
  /// The full-screen player owns the deletion and its own copy of the list;
  /// this one is refreshed by a fetch that may not come for a while, and
  /// until it does the grid shows a video whose document is gone and
  /// pagination hands it back to the player. Reconciling by id costs one pass
  /// and removes both symptoms.
  void removeVideosLocally(Iterable<String> videoIds) {
    final ids = videoIds.toSet();
    if (ids.isEmpty) return;

    final before = videoList.length;
    videoList.removeWhere((video) => ids.contains(video.id));
    if (videoList.length != before) {
      update();
    }
  }

  Future<void> fetchUserVideos(String uid, {bool isRefresh = false}) async {
    if (_loadingCompleter != null) {
      return _loadingCompleter!.future;
    }

    _loadingCompleter = Completer<void>();
    _isLoadingVideos = true;
    update();

    try {
      final ctx = 'profile:$uid';

      if (isRefresh) {
        await _videoManager.disposeAllForContext(ctx);
        videoList.clear();
        _lastVideoCursor = null;
        _hasMoreVideos = true;
      }

      if (!_hasMoreVideos) {
        return;
      }

      final page = await _profileRepository.fetchUserVideos(
        uid: uid,
        limit: _videoFetchLimit,
        after: isRefresh ? null : _lastVideoCursor,
        includeAllStates: isOwnProfile(uid),
      );
      if (page.fetchedCount == 0) {
        _hasMoreVideos = false;
      } else {
        final newVideos = page.videos;
        final existingIds = videoList.map((v) => v.id).toSet();
        final unique = newVideos
            .where((v) => !existingIds.contains(v.id))
            .toList();

        videoList.addAll(unique);
        _lastVideoCursor = page.cursor;

        if (videoList.length > _videoMemoryLimit) {
          final toRemove = videoList.length - _videoMemoryLimit;
          final removed = videoList.take(toRemove).toList();
          await _videoManager.disposeUrls(
            ctx,
            removed.map((v) => v.videoUrl).toList(),
          );
          videoList.removeRange(0, toRemove);
        }

        if (unique.length < _videoFetchLimit) {
          _hasMoreVideos = false;
        }
      }
    } catch (e, st) {
      AppLogger.warning(
        'fetchUserVideos error: $e\n$st',
        source: 'ProfileController.fetchUserVideos',
        error: e,
        stackTrace: st,
      );
      if (_isPermissionDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
        return;
      }
      if (videoList.isEmpty) {
        AdFeedback.error(
          'profileVideosUnavailableTitle'.tr,
          'profileVideosLoadUnavailableMessage'.tr,
        );
      }
    } finally {
      _isLoadingVideos = false;
      update();
      _loadingCompleter?.complete();
      _loadingCompleter = null;
    }
  }

  Future<void> refreshProfileVideos() async {
    if (user == null) {
      return;
    }
    await fetchUserVideos(user!.uid, isRefresh: true);
  }

  Future<String?> uploadCvPdf(
    String uid, {
    File? pdfFile,
    Uint8List? pdfBytes,
    Stream<List<int>>? pdfReadStream,
    int? byteSize,
  }) async {
    try {
      _clearCvUploadError();
      final ownerProblem = _ownerSessionProblemMessage(uid);
      if (ownerProblem != null) {
        final sessionInvalidTitle = 'profileInvalidSessionTitle'.tr;
        _setCvUploadError(sessionInvalidTitle, ownerProblem);
        AdFeedback.error(sessionInvalidTitle, ownerProblem);
        unawaited(_handleProtectedAccessDenied());
        return null;
      }

      final previousCvUrl = user?.cvUrl;
      final url = await _profileRepository.uploadCvPdf(
        uid,
        pdfFile: pdfFile,
        pdfBytes: pdfBytes,
        pdfReadStream: pdfReadStream,
        byteSize: byteSize,
        previousCvUrl: previousCvUrl,
      );
      user?.cvUrl = url;
      update();

      await _safeRefreshCurrentUser();

      AdFeedback.success('profileCvSavedTitle'.tr, 'profileCvSavedMessage'.tr);
      return url;
    } catch (e, st) {
      if (e is CvUploadValidationException) {
        final cvRejectedTitle = 'profileCvRejectedTitle'.tr;
        _setCvUploadError(cvRejectedTitle, e.message);
        AdFeedback.error(
          cvRejectedTitle,
          e.message,
          duration: const Duration(seconds: 6),
        );
        return null;
      }
      if (_isAccessDenied(e)) {
        final message = _cvAccessDeniedMessage(e, uid);
        final permissionDeniedTitle = 'profilePermissionDeniedTitle'.tr;
        _setCvUploadError(permissionDeniedTitle, message);
        AppLogger.error(
          'CV upload rejected',
          source: 'ProfileController.uploadCvPdf',
          error: e,
          stackTrace: st,
          metadata: {
            'code': _firebaseFailureCode(e),
            'uidMatchesAuth': _profileRepository.currentAuthUid == uid,
            'byteSize': byteSize,
            'hasFile': pdfFile != null,
            'hasBytes': pdfBytes != null,
            'hasStream': pdfReadStream != null,
          },
        );
        AdFeedback.error(
          permissionDeniedTitle,
          message,
          duration: const Duration(seconds: 6),
        );
        return null;
      }
      final message = 'profileCvAddUnavailableMessage'.tr;
      final cvAddFailedTitle = 'profileCvAddFailedTitle'.tr;
      _setCvUploadError(cvAddFailedTitle, message);
      AppLogger.error(
        'CV upload failed',
        source: 'ProfileController.uploadCvPdf',
        error: e,
        stackTrace: st,
        metadata: {
          'code': _firebaseFailureCode(e),
          'uidMatchesAuth': _profileRepository.currentAuthUid == uid,
          'byteSize': byteSize,
          'hasFile': pdfFile != null,
          'hasBytes': pdfBytes != null,
          'hasStream': pdfReadStream != null,
        },
      );
      AdFeedback.error(
        cvAddFailedTitle,
        message,
        duration: const Duration(seconds: 6),
      );
      return null;
    }
  }

  Future<void> deleteCv(String uid) async {
    try {
      await _profileRepository.deleteCv(uid, cvUrl: user?.cvUrl);

      user?.cvUrl = null;
      update();

      await _safeRefreshCurrentUser();

      AdFeedback.success(
        'profileCvDeletedTitle'.tr,
        'profileCvDeletedMessage'.tr,
      );
    } catch (e, st) {
      AppLogger.warning(
        'deleteCv error: $e',
        source: 'ProfileController.deleteCv',
        error: e,
        stackTrace: st,
      );
      if (_isAccessDenied(e)) {
        AdFeedback.error(
          'profilePermissionDeniedTitle'.tr,
          'profileCvDeletePermissionDeniedMessage'.tr,
        );
        unawaited(_handleProtectedAccessDenied());
        throw const ProfileAccessRevokedException();
      }
      AdFeedback.error(
        'profileCvDeleteFailedTitle'.tr,
        'profileCvDeleteUnavailableMessage'.tr,
      );
    }
  }

  Future<void> pauseAll() async {
    final ctx = 'profile:${user?.uid ?? ''}';
    await _videoManager.pauseAll(ctx);
  }

  void applyLocalFollowerChange({
    required String currentUserId,
    required bool shouldFollow,
  }) {
    if (user == null) {
      return;
    }

    final followers = user!.followersList;
    final alreadyFollowing = followers.contains(currentUserId);

    if (shouldFollow && !alreadyFollowing) {
      followers.add(currentUserId);
      user!.followers = user!.followers + 1;
    } else if (!shouldFollow && alreadyFollowing) {
      followers.remove(currentUserId);
      user!.followers = (user!.followers - 1).clamp(0, 1 << 30).toInt();
    }

    update();
  }
}
