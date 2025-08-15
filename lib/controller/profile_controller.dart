import 'dart:async';
import 'dart:io';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/controller/user_controller.dart';

class ProfileController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final VideoManager _videoManager = VideoManager();

  DocumentSnapshot? _lastVideoDoc;
  static const int _videoFetchLimit = 20;
  static const int _videoMemoryLimit = 25;

  AppUser? user;
  var isLoadingPhoto = false.obs;
  var videoList = <Video>[].obs;

  bool _hasMoreVideos = true;
  bool _isLoadingVideos = false;
  Completer<void>? _loadingCompleter;

  bool get hasMoreVideos => _hasMoreVideos;
  bool get isLoadingVideos => _isLoadingVideos;

  @override
  void onClose() async {
    final ctx = 'profile:${user?.uid ?? ''}';
    await _videoManager.disposeAllForContext(ctx);
    super.onClose();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getWithRetry(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    int attempt = 0;
    while (attempt < 3) {
      try {
        return await ref.get();
      } catch (e) {
        attempt++;
        if (attempt >= 3) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    throw Exception("Firestore retry failed");
  }

  Future<void> updateUserId(String uid) async {
    try {
      final doc = await _getWithRetry(_firestore.collection('users').doc(uid));
      if (!doc.exists) throw 'Profil introuvable';
      user = AppUser.fromMap(doc.data() as Map<String, dynamic>);
      update();
      await fetchUserVideos(uid, isRefresh: true);
    } catch (e, st) {
      debugPrint('❌ updateUserId: $e\n$st');
      Get.snackbar('Erreur', 'Chargement du profil impossible.',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> updateProfilePhoto(String uid, String photoPath) async {
    isLoadingPhoto.value = true;
    try {
      final ref = _storage.ref('profilePhotos/$uid');
      await ref.putFile(File(photoPath), SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      await _firestore.collection('users').doc(uid).update({'photoProfil': url});
      user?.photoProfil = url;
      update();

      await Get.find<UserController>().refreshUser();

      Get.snackbar('Succès', 'Photo mise à jour.',
          backgroundColor: Colors.green, colorText: Colors.white);
    } catch (e, st) {
      debugPrint('❌ updateProfilePhoto: $e\n$st');
      Get.snackbar('Erreur', 'Impossible de mettre à jour la photo.',
          backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      isLoadingPhoto.value = false;
    }
  }

  Future<void> fetchUserVideos(String uid, {bool isRefresh = false}) async {
    if (_loadingCompleter != null) return _loadingCompleter!.future;
    _loadingCompleter = Completer();
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

      if (!_hasMoreVideos) return;

      Query q = _firestore
          .collection('videos')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'ready')
          .orderBy('updatedAt', descending: true)
          .limit(_videoFetchLimit);

      if (!isRefresh && _lastVideoDoc != null) {
        q = q.startAfter([_lastVideoDoc!.get('updatedAt')]);
      }

      final snap = await q.get();
      if (snap.docs.isEmpty) {
        _hasMoreVideos = false;
      } else {
        final newVideos = snap.docs
            .map((d) => Video.fromMap(d.data() as Map<String, dynamic>))
            .where((v) => v.videoUrl.isNotEmpty)
            .toList();

        final ids = videoList.map((v) => v.id).toSet();
        final unique = newVideos.where((v) => !ids.contains(v.id)).toList();

        videoList.addAll(unique);
        _lastVideoDoc = snap.docs.last;

        if (videoList.length > _videoMemoryLimit) {
          final toRemove = videoList.length - _videoMemoryLimit;
          final removed = videoList.take(toRemove).toList();
          final urlsToDispose = removed.map((v) => v.videoUrl).toList();
          await _videoManager.disposeUrls(ctx, urlsToDispose);
          videoList.removeRange(0, toRemove);
        }

        final urls = videoList.map((v) => v.videoUrl).toList();

        if (isRefresh && videoList.isNotEmpty) {
          await _videoManager.initializeController(ctx, videoList.first.videoUrl);
          _videoManager.pauseAllExcept(ctx, videoList.first.videoUrl);
          _videoManager.preloadSurrounding(ctx, urls, 0);

          for (int i = 1; i < 4 && i < videoList.length; i++) {
            unawaited(_videoManager.initializeController(ctx, videoList[i].videoUrl, isPreload: true));
          }
        }

        if (unique.length < _videoFetchLimit) _hasMoreVideos = false;
      }
    } catch (e, st) {
      debugPrint('❌ fetchUserVideos: $e\n$st');
      if (videoList.isEmpty) {
        Get.snackbar('Erreur', 'Chargement des vidéos impossible.',
            backgroundColor: Colors.red, colorText: Colors.white);
      }
    } finally {
      _isLoadingVideos = false;
      update();
      _loadingCompleter?.complete();
      _loadingCompleter = null;
    }
  }

  Future<void> refreshProfileVideos() async {
    if (user == null) return;
    await fetchUserVideos(user!.uid, isRefresh: true);
  }

  Future<void> updateUserProfile(AppUser upd) async {
    try {
      await _firestore.collection('users').doc(upd.uid).update(upd.toMap());
      user = upd;
      update();
      await Get.find<UserController>().refreshUser();
      Get.snackbar('Succès', 'Profil mis à jour.',
          backgroundColor: Colors.green, colorText: Colors.white);
    } catch (e) {
      debugPrint('❌ updateUserProfile: $e');
      Get.snackbar('Erreur', 'Impossible de mettre à jour le profil.',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> followUser() async {
    try {
      final current = FirebaseAuth.instance.currentUser?.uid;
      final uid = user?.uid;
      if (current == null || uid == null || current == uid) return;

      final doc = await _getWithRetry(_firestore.collection('users').doc(current));
      final followings = List<String>.from(doc.get('followings') ?? []);
      if (followings.contains(uid)) {
        followings.remove(uid);
        user!.followers--;
      } else {
        followings.add(uid);
        user!.followers++;
      }

      await _firestore.collection('users').doc(current).update({'followings': followings});
      await _firestore.collection('users').doc(uid).update({'followers': user!.followers});
      update();
    } catch (e) {
      debugPrint('❌ followUser: $e');
      Get.snackbar('Erreur', 'Action de suivi impossible.',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> pauseAll() async {
    final ctx = 'profile:${user?.uid ?? ''}';
    await _videoManager.pauseAll(ctx);
  }

  AppUser? getLoggedInUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == user?.uid ? user : null;
  }

  bool get isOwnProfile {
    final current = FirebaseAuth.instance.currentUser?.uid;
    return current != null && current == user?.uid;
  }

  // Dans ProfileController

Future<void> uploadCvPdf(String uid, File pdfFile) async {
  try {
    final ref = _storage.ref('cvs/$uid/cv_${DateTime.now().millisecondsSinceEpoch}.pdf');
    final metadata = SettableMetadata(contentType: 'application/pdf');
    final uploadTask = await ref.putFile(pdfFile, metadata);
    final url = await uploadTask.ref.getDownloadURL();

    await _firestore.collection('users').doc(uid).update({'cvUrl': url});
    user?.cvUrl = url;
    update();
    Get.snackbar('Succès', 'CV ajouté ou mis à jour.', backgroundColor: Colors.green, colorText: Colors.white);
  } catch (e) {
    debugPrint('❌ uploadCvPdf: $e');
    Get.snackbar('Erreur', 'Impossible d’ajouter le CV.', backgroundColor: Colors.red, colorText: Colors.white);
  }
}

Future<void> deleteCv(String uid) async {
  try {
    if (user?.cvUrl != null) {
      final ref = _storage.refFromURL(user!.cvUrl!);
      await ref.delete();
    }
    await _firestore.collection('users').doc(uid).update({'cvUrl': FieldValue.delete()});
    user?.cvUrl = null;
    update();
    Get.snackbar('Succès', 'CV supprimé.', backgroundColor: Colors.green, colorText: Colors.white);
  } catch (e) {
    debugPrint('❌ deleteCv: $e');
    Get.snackbar('Erreur', 'Impossible de supprimer le CV.', backgroundColor: Colors.red, colorText: Colors.white);
  }
}

}
