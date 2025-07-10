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

  Future<void> updateUserId(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
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

      await Get.find<UserController>().refreshUserData();

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
      if (isRefresh) {
        final ctx = 'profile:$uid';
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

        final ctx = 'profile:$uid';
        final urls = videoList.map((v) => v.videoUrl).toList();

        /// ✅ Initialiser et précharger la première vidéo pour lecture instantanée
        if (isRefresh && videoList.isNotEmpty) {
          await _videoManager.initializeController(ctx, videoList.first.videoUrl);
          _videoManager.pauseAllExcept(ctx, videoList.first.videoUrl);
          _videoManager.preloadSurrounding(ctx, urls, 0);

          /// ✅ Préchargement des suivantes (style TikTok)
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
      await Get.find<UserController>().refreshUserData();
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

      final snap = await _firestore.collection('users').doc(current).get();
      final followings = List<String>.from(snap.get('followings') ?? []);
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

  /// ✅ Pour pause globale dans ProfileScreen
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

}
