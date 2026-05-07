import 'dart:async';
import 'dart:io';

import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProfileFieldDelete {
  const ProfileFieldDelete._();
}

class ProfileAccessRevokedException implements Exception {
  const ProfileAccessRevokedException();
}

class ProfileLoadException implements Exception {
  const ProfileLoadException(this.message);

  final String message;
}

class ProfileController extends GetxController {
  static const ProfileFieldDelete deleteField = ProfileFieldDelete._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final VideoManager _videoManager = VideoManager();

  AppUser? user;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;

  final isLoadingPhoto = false.obs;
  final videoList = <Video>[].obs;
  bool isLoadingUser = false;
  String? profileLoadErrorTitle;
  String? profileLoadErrorMessage;

  DocumentSnapshot<Map<String, dynamic>>? _lastVideoDoc;
  static const int _videoFetchLimit = 20;
  static const int _videoMemoryLimit = 25;

  bool _hasMoreVideos = true;
  bool _isLoadingVideos = false;
  Completer<void>? _loadingCompleter;

  bool get hasMoreVideos => _hasMoreVideos;
  bool get isLoadingVideos => _isLoadingVideos;

  bool _isPermissionDenied(Object error) =>
      error is FirebaseException && error.code == 'permission-denied';

  bool _isTransientFirestoreError(Object error) {
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

  String _profileLoadErrorMessage(Object error) {
    if (error is ProfileLoadException) {
      return error.message;
    }

    if (_isPermissionDenied(error)) {
      return 'Vous n avez pas acces a ce profil avec la session actuelle.';
    }

    if (_isTransientFirestoreError(error)) {
      return 'Connexion instable. Verifiez votre reseau puis reessayez.';
    }

    return 'Chargement du profil impossible. Reessayez dans quelques instants.';
  }

  Future<void> _handleProtectedAccessDenied() async {
    if (!Get.isRegistered<UserController>()) {
      return;
    }

    await Get.find<UserController>().handleProtectedAccessDenied(
      fallbackTitle: 'Acces indisponible',
      fallbackMessage:
          'Votre session a ete fermee pour proteger votre compte. Veuillez vous reconnecter.',
    );
  }

  @override
  void onClose() async {
    final ctx = 'profile:${user?.uid ?? ''}';
    await _videoManager.disposeAllForContext(ctx);
    await _userSubscription?.cancel();
    super.onClose();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getWithRetry(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    int attempt = 0;
    while (attempt < 3) {
      try {
        return await ref.get();
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

  Future<void> updateUserId(String uid) async {
    isLoadingUser = true;
    profileLoadErrorTitle = null;
    profileLoadErrorMessage = null;
    update();

    try {
      final doc = await _getWithRetry(_firestore.collection('users').doc(uid));
      if (!doc.exists) {
        throw const ProfileLoadException('Profil introuvable.');
      }

      user = AppUser.fromMap(doc.data()!);
      isLoadingUser = false;
      update();

      _startUserListener(uid);
      await fetchUserVideos(uid, isRefresh: true);
    } catch (e, st) {
      debugPrint('updateUserId error: $e\n$st');
      isLoadingUser = false;
      profileLoadErrorTitle = 'Profil indisponible';
      profileLoadErrorMessage = _profileLoadErrorMessage(e);
      update();
      if (_isPermissionDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
        return;
      }
      Get.snackbar(
        'Erreur',
        'Chargement du profil impossible.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _startUserListener(String uid) {
    _userSubscription?.cancel();
    _userSubscription =
        _firestore.collection('users').doc(uid).snapshots().listen(
      (snapshot) {
        if (!snapshot.exists) {
          return;
        }
        final data = snapshot.data();
        if (data == null) {
          return;
        }
        user = AppUser.fromMap(data);
        update();
      },
      onError: (error, stackTrace) {
        debugPrint('profile user listener error: $error\n$stackTrace');
        if (user == null) {
          profileLoadErrorTitle = 'Profil indisponible';
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
      await _firestore
          .collection('users')
          .doc(updatedUser.uid)
          .set(updatedUser.toMap(), SetOptions(merge: true));

      user = updatedUser;
      update();

      if (Get.isRegistered<UserController>()) {
        await Get.find<UserController>().refreshUser();
      }
    } catch (e, st) {
      debugPrint('updateUserProfile error: $e\n$st');
      if (_isPermissionDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
        throw const ProfileAccessRevokedException();
      }
      Get.snackbar(
        'Erreur',
        'Impossible de mettre a jour le profil.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
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
      if (patch.isEmpty) {
        return;
      }

      final sanitized = _sanitizePatch(patch);
      if (sanitized.isEmpty) {
        return;
      }

      final advancedKeys = <String>{
        'playerProfile',
        'clubProfile',
        'agentProfile',
        'eventOrganizerProfile',
      };

      final finalPatch = Map<String, dynamic>.from(sanitized);
      final needsDeepMerge = finalPatch.keys.any(advancedKeys.contains);

      if (needsDeepMerge) {
        final doc =
            await _getWithRetry(_firestore.collection('users').doc(uid));
        final existing = doc.data() ?? <String, dynamic>{};

        for (final key in advancedKeys) {
          if (!finalPatch.containsKey(key)) {
            continue;
          }

          final incoming = finalPatch[key];
          if (incoming is FieldValue) {
            continue;
          }
          if (incoming is! Map) {
            continue;
          }

          final old = existing[key];
          if (old is Map) {
            finalPatch[key] = _deepMergeMap(
              Map<String, dynamic>.from(old),
              Map<String, dynamic>.from(incoming),
            );
          } else {
            finalPatch[key] = Map<String, dynamic>.from(incoming);
          }
        }
      }

      await _firestore.collection('users').doc(uid).update(finalPatch);

      if (alsoUpdateLocalUser && user != null && user!.uid == uid) {
        _applyPatchToLocalUser(finalPatch);
        update();
      }

      if (refreshGlobalUser && Get.isRegistered<UserController>()) {
        await Get.find<UserController>().refreshUser();
      }
    } catch (e, st) {
      debugPrint('updateProfilePatch error: $e\n$st');
      if (_isPermissionDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
        throw const ProfileAccessRevokedException();
      }
      Get.snackbar(
        'Erreur',
        'Impossible de mettre a jour le profil.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      rethrow;
    }
  }

  Map<String, dynamic> _sanitizePatch(Map<String, dynamic> patch) {
    final out = <String, dynamic>{};

    void addIfValid(String key, dynamic value) {
      if (value == null) {
        return;
      }

      if (value is ProfileFieldDelete) {
        out[key] = FieldValue.delete();
        return;
      }

      if (value is FieldValue) {
        out[key] = value;
        return;
      }

      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) {
          return;
        }
        out[key] = trimmed;
        return;
      }

      if (value is List) {
        if (value.isEmpty) {
          return;
        }
        out[key] = value;
        return;
      }

      if (value is Map) {
        if (value.isEmpty) {
          return;
        }
        out[key] = value;
        return;
      }

      out[key] = value;
    }

    patch.forEach(addIfValid);
    return out;
  }

  Map<String, dynamic> _deepMergeMap(
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
      if (value is! FieldValue) {
        u.photoProfil = value as String;
      }
    }

    void applyNullableString(String key, void Function(String?) setter) {
      if (!patch.containsKey(key)) {
        return;
      }
      final value = patch[key];
      if (value is FieldValue) {
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
      if (value is FieldValue) {
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
      if (value is FieldValue) {
        u.performances = null;
      } else if (value is Map) {
        u.performances = Map<String, double>.from(
          value.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
        );
      }
    }

    if (patch.containsKey('cvUrl')) {
      final value = patch['cvUrl'];
      if (value is FieldValue) {
        u.cvUrl = null;
      } else {
        u.cvUrl = value as String?;
      }
    }

    if (patch.containsKey('birthDate')) {
      final value = patch['birthDate'];
      if (value is FieldValue) {
        u.birthDate = null;
      } else if (value is Timestamp) {
        u.birthDate = value.toDate();
      } else if (value is DateTime) {
        u.birthDate = value;
      }
    }

    if (patch.containsKey('languages')) {
      final value = patch['languages'];
      if (value is FieldValue) {
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

    void applyMap(String key, void Function(Map<String, dynamic>) setter) {
      if (!patch.containsKey(key)) {
        return;
      }
      final value = patch[key];
      if (value is FieldValue) {
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
      final ref = _storage.ref('profilePhotos/$uid');
      await ref.putFile(
        File(photoPath),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();

      await _firestore.collection('users').doc(uid).update({
        'photoProfil': url,
      });

      user?.photoProfil = url;
      update();

      await Get.find<UserController>().refreshUser();

      Get.snackbar(
        'Succes',
        'Photo mise a jour.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e, st) {
      debugPrint('updateProfilePhoto error: $e\n$st');
      if (_isPermissionDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
        throw const ProfileAccessRevokedException();
      }
      Get.snackbar(
        'Erreur',
        'Impossible de mettre a jour la photo.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      isLoadingPhoto.value = false;
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
        _lastVideoDoc = null;
        _hasMoreVideos = true;
      }

      if (!_hasMoreVideos) {
        return;
      }

      Query<Map<String, dynamic>> query = _firestore
          .collection('videos')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'ready')
          .orderBy('updatedAt', descending: true)
          .limit(_videoFetchLimit);

      if (!isRefresh && _lastVideoDoc != null) {
        query = query.startAfter([_lastVideoDoc!.get('updatedAt')]);
      }

      final snap = await query.get();
      if (snap.docs.isEmpty) {
        _hasMoreVideos = false;
      } else {
        final newVideos = snap.docs
            .map((d) => Video.fromDoc(d))
            .where((v) => v.videoUrl.isNotEmpty)
            .toList();

        final existingIds = videoList.map((v) => v.id).toSet();
        final unique =
            newVideos.where((v) => !existingIds.contains(v.id)).toList();

        videoList.addAll(unique);
        _lastVideoDoc = snap.docs.last;

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
      debugPrint('fetchUserVideos error: $e\n$st');
      if (_isPermissionDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
        return;
      }
      if (videoList.isEmpty) {
        Get.snackbar(
          'Erreur',
          'Chargement des videos impossible.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
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

  Future<void> uploadCvPdf(String uid, File pdfFile) async {
    try {
      final ref = _storage
          .ref('cvs/$uid/cv_${DateTime.now().millisecondsSinceEpoch}.pdf');
      final metadata = SettableMetadata(contentType: 'application/pdf');
      final uploadTask = await ref.putFile(pdfFile, metadata);
      final url = await uploadTask.ref.getDownloadURL();

      await _firestore.collection('users').doc(uid).update({'cvUrl': url});
      user?.cvUrl = url;
      update();

      Get.snackbar(
        'Succes',
        'CV ajoute ou mis a jour.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('uploadCvPdf error: $e');
      if (_isPermissionDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
        throw const ProfileAccessRevokedException();
      }
      Get.snackbar(
        'Erreur',
        'Impossible d\'ajouter le CV.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> deleteCv(String uid) async {
    try {
      if (user?.cvUrl != null) {
        await _storage.refFromURL(user!.cvUrl!).delete();
      }

      await _firestore.collection('users').doc(uid).update({
        'cvUrl': FieldValue.delete(),
      });

      user?.cvUrl = null;
      update();

      Get.snackbar(
        'Succes',
        'CV supprime.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('deleteCv error: $e');
      if (_isPermissionDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
        throw const ProfileAccessRevokedException();
      }
      Get.snackbar(
        'Erreur',
        'Impossible de supprimer le CV.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> pauseAll() async {
    final ctx = 'profile:${user?.uid ?? ''}';
    await _videoManager.pauseAll(ctx);
  }

  bool get isOwnProfile {
    final current = FirebaseAuth.instance.currentUser?.uid;
    return current != null && current == user?.uid;
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
