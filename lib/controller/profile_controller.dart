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

  AppUser? user;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userSubscription;

  // UI / State
  final isLoadingPhoto = false.obs;
  final videoList = <Video>[].obs;

  DocumentSnapshot<Map<String, dynamic>>? _lastVideoDoc;
  static const int _videoFetchLimit = 20;
  static const int _videoMemoryLimit = 25;

  bool _hasMoreVideos = true;
  bool _isLoadingVideos = false;
  Completer<void>? _loadingCompleter;

  bool get hasMoreVideos => _hasMoreVideos;
  bool get isLoadingVideos => _isLoadingVideos;

  // =========================
  // Lifecycle
  // =========================

  @override
  void onClose() async {
    final ctx = 'profile:${user?.uid ?? ''}';
    await _videoManager.disposeAllForContext(ctx);
    await _userSubscription?.cancel();
    super.onClose();
  }

  // =========================
  // Firestore safe fetch
  // =========================

  Future<DocumentSnapshot<Map<String, dynamic>>> _getWithRetry(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    int attempt = 0;
    while (attempt < 3) {
      try {
        return await ref.get();
      } catch (_) {
        attempt++;
        if (attempt >= 3) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    throw Exception('Firestore retry failed');
  }

  // =========================
  // Profil loading
  // =========================

  Future<void> updateUserId(String uid) async {
    try {
      final doc = await _getWithRetry(_firestore.collection('users').doc(uid));
      if (!doc.exists) throw 'Profil introuvable';

      user = AppUser.fromMap(doc.data()!);
      update();

      _startUserListener(uid);
      await fetchUserVideos(uid, isRefresh: true);
    } catch (e, st) {
      debugPrint('❌ updateUserId: $e\n$st');
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
    _userSubscription = _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
      (snapshot) {
        if (!snapshot.exists) return;
        final data = snapshot.data();
        if (data == null) return;
        user = AppUser.fromMap(data);
        update();
      },
      onError: (error, stackTrace) {
        debugPrint('❌ profile user listener error: $error\n$stackTrace');
      },
    );
  }

  // =========================
  // 🔥 MÉTHODE MAÎTRESSE
  // =========================

  /// ✅ Mise à jour complète du profil (tous rôles confondus)
  Future<void> updateUserProfile(AppUser updatedUser) async {
    try {
      await _firestore
          .collection('users')
          .doc(updatedUser.uid)
          .set(updatedUser.toMap(), SetOptions(merge: true));

      user = updatedUser;
      update();

      // Synchronisation globale
      if (Get.isRegistered<UserController>()) {
        await Get.find<UserController>().refreshUser();
      }
    } catch (e, st) {
      debugPrint('❌ updateUserProfile: $e\n$st');
      Get.snackbar(
        'Erreur',
        'Impossible de mettre à jour le profil.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      rethrow;
    }
  }

  // =========================
  // ✅ PATCH UPDATE (anti-régression)
  // =========================
  /// Mise à jour partielle ultra-safe :
  /// - n’écrase pas les champs non concernés
  /// - supprime les null/"" inutiles par défaut
  /// - permet FieldValue.delete() si explicitement fourni
  /// - deep-merge sur les maps avancées (playerProfile/clubProfile/agentProfile)
  Future<void> updateProfilePatch(
    String uid,
    Map<String, dynamic> patch, {
    bool refreshGlobalUser = true,
    bool alsoUpdateLocalUser = true,
  }) async {
    try {
      if (patch.isEmpty) return;

      // 1) Nettoyage du patch (évite null/"" qui effacent)
      final sanitized = _sanitizePatch(patch);

      if (sanitized.isEmpty) return;

      // 2) Cas particulier : maps avancées => deep merge
      //    Pour éviter d’écraser tout playerProfile quand on change un champ.
      final advancedKeys = <String>{
        'playerProfile',
        'clubProfile',
        'agentProfile',
        'eventOrganizerProfile',
      };

      final Map<String, dynamic> finalPatch =
          Map<String, dynamic>.from(sanitized);

      // Fetch doc uniquement si on doit deep-merge au lieu d’écraser
      final needsDeepMerge = finalPatch.keys.any(advancedKeys.contains);
      if (needsDeepMerge) {
        final doc =
            await _getWithRetry(_firestore.collection('users').doc(uid));
        final existing = doc.data() ?? {};

        for (final key in advancedKeys) {
          if (!finalPatch.containsKey(key)) continue;

          final incoming = finalPatch[key];

          // Si l’appelant a explicitement mis FieldValue.delete(), on respecte.
          if (incoming is FieldValue) continue;

          // Si incoming n’est pas une Map, on laisse tel quel (cas rare)
          if (incoming is! Map) continue;

          final old = existing[key];
          if (old is Map) {
            final merged = _deepMergeMap(
              Map<String, dynamic>.from(old),
              Map<String, dynamic>.from(incoming),
            );
            finalPatch[key] = merged;
          } else {
            // Rien avant : on pose la map
            finalPatch[key] = Map<String, dynamic>.from(incoming);
          }
        }
      }

      // 3) Update Firestore
      await _firestore.collection('users').doc(uid).update(finalPatch);

      // 4) Mise à jour locale (pour refresh UI immédiat)
      if (alsoUpdateLocalUser && user != null && user!.uid == uid) {
        _applyPatchToLocalUser(finalPatch);
        update();
      }

      // 5) Sync globale (UserController) pour le reste de l’app
      if (refreshGlobalUser && Get.isRegistered<UserController>()) {
        await Get.find<UserController>().refreshUser();
      }
    } catch (e, st) {
      debugPrint('❌ updateProfilePatch: $e\n$st');
      Get.snackbar(
        'Erreur',
        'Impossible de mettre à jour le profil.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      rethrow;
    }
  }

  // =========================
  // Helpers SAFE
  // =========================

  /// Enlève les null et Strings vides par défaut.
  /// ⚠️ Conserve FieldValue.delete() si explicitement fourni.
  Map<String, dynamic> _sanitizePatch(Map<String, dynamic> patch) {
    final out = <String, dynamic>{};

    void addIfValid(String key, dynamic value) {
      if (value == null) return;

      // Autoriser delete explicitement
      if (value is FieldValue) {
        out[key] = value;
        return;
      }

      // string vide -> on ignore (évite d’écraser)
      if (value is String) {
        final t = value.trim();
        if (t.isEmpty) return;
        out[key] = t;
        return;
      }

      // liste vide -> on ignore (évite d’écraser) sauf si tu veux explicitement vider
      if (value is List) {
        if (value.isEmpty) return;
        out[key] = value;
        return;
      }

      // map vide -> on ignore
      if (value is Map) {
        if (value.isEmpty) return;
        out[key] = value;
        return;
      }

      out[key] = value;
    }

    patch.forEach(addIfValid);
    return out;
  }

  /// Deep merge récursif pour Map<String,dynamic>
  /// - merge les maps imbriquées
  /// - écrase les scalaires/listes
  Map<String, dynamic> _deepMergeMap(
    Map<String, dynamic> base,
    Map<String, dynamic> incoming,
  ) {
    final result = Map<String, dynamic>.from(base);

    incoming.forEach((k, v) {
      if (v == null) return; // ignore null
      final old = result[k];

      if (old is Map && v is Map) {
        result[k] = _deepMergeMap(
          Map<String, dynamic>.from(old),
          Map<String, dynamic>.from(v),
        );
      } else {
        result[k] = v;
      }
    });

    return result;
  }

  /// Applique un patch localement sur `user` pour éviter un refetch complet.
  /// Ici on gère les champs principaux + maps avancées.
  void _applyPatchToLocalUser(Map<String, dynamic> patch) {
    final u = user;
    if (u == null) return;

    // Identité
    if (patch.containsKey('nom')) u.nom = patch['nom'] as String;
    if (patch.containsKey('photoProfil')) {
      u.photoProfil = patch['photoProfil'] as String;
    }

    // Champs simples (si présents)
    if (patch.containsKey('phone')) u.phone = patch['phone'] as String?;
    if (patch.containsKey('bio')) u.bio = patch['bio'] as String?;
    if (patch.containsKey('position')) {
      u.position = patch['position'] as String?;
    }
    if (patch.containsKey('team')) u.team = patch['team'] as String?;
    if (patch.containsKey('clubActuel')) {
      u.clubActuel = patch['clubActuel'] as String?;
    }

    if (patch.containsKey('nombreDeMatchs')) {
      u.nombreDeMatchs = patch['nombreDeMatchs'] as int?;
    }
    if (patch.containsKey('buts')) u.buts = patch['buts'] as int?;
    if (patch.containsKey('assistances')) {
      u.assistances = patch['assistances'] as int?;
    }

    if (patch.containsKey('nomClub')) u.nomClub = patch['nomClub'] as String?;
    if (patch.containsKey('ligue')) u.ligue = patch['ligue'] as String?;

    if (patch.containsKey('entreprise')) {
      u.entreprise = patch['entreprise'] as String?;
    }
    if (patch.containsKey('nombreDeRecrutements')) {
      u.nombreDeRecrutements = patch['nombreDeRecrutements'] as int?;
    }

    // Docs
    if (patch.containsKey('cvUrl')) {
      final v = patch['cvUrl'];
      if (v is FieldValue) {
        // delete
        u.cvUrl = null;
      } else {
        u.cvUrl = v as String?;
      }
    }

    // Transverses (optionnels)
    if (patch.containsKey('birthDate')) {
      final v = patch['birthDate'];
      if (v is FieldValue) {
        u.birthDate = null;
      } else if (v is Timestamp) {
        u.birthDate = v.toDate();
      } else if (v is DateTime) {
        u.birthDate = v;
      }
    }
    if (patch.containsKey('country')) u.country = patch['country'] as String?;
    if (patch.containsKey('city')) u.city = patch['city'] as String?;
    if (patch.containsKey('region')) u.region = patch['region'] as String?;
    if (patch.containsKey('languages')) {
      u.languages =
          (patch['languages'] as List).map((e) => e.toString()).toList();
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

    // Avancés (maps)
    void applyMap(String key, void Function(Map<String, dynamic>) setter) {
      if (!patch.containsKey(key)) return;
      final v = patch[key];
      if (v is FieldValue) {
        // delete -> null
        setter(<String, dynamic>{});
        return;
      }
      if (v is Map) setter(Map<String, dynamic>.from(v));
    }

    applyMap('playerProfile', (m) => u.playerProfile = m);
    applyMap('clubProfile', (m) => u.clubProfile = m);
    applyMap('agentProfile', (m) => u.agentProfile = m);
  }

  // =========================
  // Photo de profil
  // =========================

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
        'Succès',
        'Photo mise à jour.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e, st) {
      debugPrint('❌ updateProfilePhoto: $e\n$st');
      Get.snackbar(
        'Erreur',
        'Impossible de mettre à jour la photo.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      isLoadingPhoto.value = false;
    }
  }

  // =========================
  // Vidéos (inchangé)
  // =========================

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

      Query<Map<String, dynamic>> q = _firestore
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
            .map((d) => Video.fromDoc(d))
            .where((v) => v.videoUrl.isNotEmpty)
            .toList();

        final ids = videoList.map((v) => v.id).toSet();
        final unique = newVideos.where((v) => !ids.contains(v.id)).toList();

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
      debugPrint('❌ fetchUserVideos: $e\n$st');
      if (videoList.isEmpty) {
        Get.snackbar(
          'Erreur',
          'Chargement des vidéos impossible.',
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
    if (user == null) return;
    await fetchUserVideos(user!.uid, isRefresh: true);
  }

  // =========================
  // CV
  // =========================

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
        'Succès',
        'CV ajouté ou mis à jour.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('❌ uploadCvPdf: $e');
      Get.snackbar(
        'Erreur',
        'Impossible d’ajouter le CV.',
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
        'Succès',
        'CV supprimé.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('❌ deleteCv: $e');
      Get.snackbar(
        'Erreur',
        'Impossible de supprimer le CV.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // =========================
  // Utils
  // =========================

  Future<void> pauseAll() async {
    final ctx = 'profile:${user?.uid ?? ''}';
    await _videoManager.pauseAll(ctx);
  }

  bool get isOwnProfile {
    final current = FirebaseAuth.instance.currentUser?.uid;
    return current != null && current == user?.uid;
  }

  /// Met à jour localement la liste des abonnés pour un affichage immédiat.
  /// Utilisé pour rendre l'UI réactive avant la confirmation Firestore.
  void applyLocalFollowerChange({
    required String currentUserId,
    required bool shouldFollow,
  }) {
    if (user == null) return;

    final followers = user!.followersList;
    final alreadyFollowing = followers.contains(currentUserId);

    if (shouldFollow && !alreadyFollowing) {
      followers.add(currentUserId);
      user!.followers = user!.followers + 1;
    } else if (!shouldFollow && alreadyFollowing) {
      followers.remove(currentUserId);
      user!.followers = (user!.followers - 1).clamp(0, double.maxFinite).toInt();
    }

    update();
  }
}
