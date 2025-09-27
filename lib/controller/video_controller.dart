import 'dart:async';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/video.dart';
import '../widgets/video_manager.dart';

class VideoController extends GetxController {
  final String contextKey;

  VideoController({required this.contextKey});

  // Etat UI
  final videoList = <Video>[].obs;
  final currentIndex = 0.obs;

  // Pagination
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _isLoading = false;
  static const int _limit = 10;

  // Accès VideoManager
  final VideoManager _videoManager = VideoManager();
  VideoManager get videoManager => _videoManager;

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  // Verrou de fetch
  Completer<void>? _fetchLock;

  // Ecoutes/temporisations
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _videoSubscription;
  Timer? _streamDebouncer;
  Timer? _indexDebouncer;

  @override
  void onInit() {
    super.onInit();

    // Throttle sur le changement d'index
    ever<int>(currentIndex, (idx) {
      _indexDebouncer?.cancel();
      _indexDebouncer = Timer(const Duration(milliseconds: 200), () {
        _onCurrentIndexChangedThrottled(idx);
      });
    });

    listenToVideos();
  }

  @override
  void onClose() {
    _streamDebouncer?.cancel();
    _videoSubscription?.cancel();
    _indexDebouncer?.cancel();
    unawaited(videoManager.disposeAllForContext(contextKey));
    super.onClose();
  }

  /// Écoute temps réel Firestore des vidéos prêtes
  void listenToVideos() {
    _videoSubscription?.cancel();
    _videoSubscription = FirebaseFirestore.instance
        .collection('videos')
        .where('status', isEqualTo: 'ready')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      _streamDebouncer?.cancel();
      _streamDebouncer = Timer(const Duration(milliseconds: 120), () {
        try {
          final incoming = snapshot.docs
              .map((doc) => Video.fromDoc(doc))
              .where((v) => v.videoUrl.isNotEmpty)
              .toList();

          // Fusion par ID pour préserver les éléments déjà présents
          final byId = {for (final v in videoList) v.id: v};
          for (final v in incoming) {
            byId[v.id] = v;
          }
          videoList.value = incoming.map((v) => byId[v.id]!).toList();

          _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMore = snapshot.docs.length >= _limit;
        } catch (e) {
          debugPrint('❌ listenToVideos merge error: $e');
        }
      });
    }, onError: (e) {
      debugPrint('❌ Erreur stream vidéos: $e');
    });
  }

  /// Récupération paginée
  Future<bool> fetchPaginatedVideos({bool isRefresh = false}) async {
    if (_isLoading || !_hasMore || (_fetchLock?.isCompleted == false)) {
      return false;
    }

    _isLoading = true;
    _fetchLock = Completer<void>();

    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('videos')
          .where('status', isEqualTo: 'ready')
          .orderBy('updatedAt', descending: true)
          .limit(_limit);

      if (!isRefresh && _lastDoc != null) {
        query = query.startAfterDocument(_lastDoc!);
      }

      final snap = await query.get();
      if (snap.docs.isEmpty) {
        _hasMore = false;
        _fetchLock?.complete();
        return false;
      }

      final fetched = snap.docs
          .map((d) => Video.fromDoc(d))
          .where((v) => v.videoUrl.isNotEmpty)
          .toList();

      if (isRefresh) {
        videoList.assignAll(fetched);
      } else {
        final currentIds = videoList.map((v) => v.id).toSet();
        final unique = fetched.where((v) => !currentIds.contains(v.id)).toList();
        videoList.addAll(unique);
      }

      if (isRefresh && videoList.isNotEmpty) {
        await _setupInitialPlayback();
      }

      _lastDoc = snap.docs.last;
      if (fetched.length < _limit) _hasMore = false;

      _fetchLock?.complete();
      return true;
    } catch (e) {
      debugPrint('❌ fetchPaginatedVideos error: $e');
      _fetchLock?.completeError(e);
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /// Force un rechargement complet
  Future<bool> refreshVideos() async {
    try {
      await videoManager.disposeAllForContext(contextKey);
      _lastDoc = null;
      _hasMore = true;
      videoList.clear();
      return await fetchPaginatedVideos(isRefresh: true);
    } catch (e) {
      debugPrint('❌ refreshVideos error: $e');
      return false;
    }
  }

  /// Prépare la lecture de la première vidéo + précharge voisins
  Future<void> _setupInitialPlayback() async {
    currentIndex.value = 0;
    final urls = videoList.map((v) => v.videoUrl).toList();
    final firstUrl = urls.first;

    await videoManager.disposeAllForContext(contextKey);

    await videoManager.initializeController(
      contextKey,
      firstUrl,
      autoPlay: true,
      activeUrl: firstUrl,
    );

    await videoManager.pauseAllExcept(contextKey, firstUrl);
    videoManager.preloadSurrounding(contextKey, urls, 0, activeUrl: firstUrl);

    // Précharge léger (ajuste selon réseau si besoin)
    const preloadCount = 3;
    for (int i = 1; i < preloadCount && i < urls.length; i++) {
      unawaited(
        videoManager.initializeController(
          contextKey,
          urls[i],
          isPreload: true,
          activeUrl: firstUrl,
        ),
      );
    }
  }

  /// Throttle du changement d'index
  Future<void> _onCurrentIndexChangedThrottled(int index) async {
    if (index < 0 || index >= videoList.length) return;

    final url = videoList[index].videoUrl;
    final urls = videoList.map((v) => v.videoUrl).toList();
    await _processVideoPlaybackChange(urls, index, url);

    // Trigger pagination en avance
    if (index >= videoList.length - 2 && hasMore && !_isLoading) {
      unawaited(fetchPaginatedVideos());
    }
  }

  /// Applique la lecture pour l'URL active + préchargement
  Future<void> _processVideoPlaybackChange(
    List<String> urls,
    int idx,
    String activeUrl,
  ) async {
    await videoManager.pauseAllExcept(contextKey, activeUrl);
    videoManager.preloadSurrounding(contextKey, urls, idx, activeUrl: activeUrl);

    CachedVideoPlayerPlus? player =
        videoManager.getController(contextKey, activeUrl);
    final ctrl = player?.controller;

    if (ctrl == null || !ctrl.value.isInitialized || ctrl.value.hasError) {
      try {
        await videoManager.initializeController(
          contextKey,
          activeUrl,
          autoPlay: false,
          activeUrl: activeUrl,
        );
      } catch (e) {
        debugPrint('❌ Error init controller (indexChanged): $e');
      }
    }
  }

  Future<void> pauseAll() => videoManager.pauseAll(contextKey);

  // ------------------------------------------------------------------
  //                        FIRESTORE MUTATIONS
  // ------------------------------------------------------------------

  /// Toggle like via transaction (atomique)
  Future<bool> likeVideo(String videoId, String userId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      return await FirebaseFirestore.instance.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return false;

        final data = snap.data() ?? {};
        final List<dynamic> likesDyn = (data['likes'] ?? []) as List<dynamic>;
        final likes = likesDyn.map((e) => e.toString()).toList();

        final hasLiked = likes.contains(userId);
        tx.update(ref, hasLiked
            ? {'likes': FieldValue.arrayRemove([userId])}
            : {'likes': FieldValue.arrayUnion([userId])});
        return true;
      });
    } catch (e) {
      debugPrint('❌ likeVideo error: $e');
      return false;
    }
  }

  /// Incrémente le partage (pas besoin d’unicité)
  Future<bool> partagerVideo(String videoId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      await ref.update({'shareCount': FieldValue.increment(1)});
      return true;
    } catch (e) {
      debugPrint('❌ partagerVideo error: $e');
      return false;
    }
  }

  /// Signaler la vidéo : n'incrémente que si l'utilisateur n'a pas déjà signalé
  Future<bool> signalerVideo(String videoId, String userId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      return await FirebaseFirestore.instance.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return false;

        final data = snap.data() ?? {};
        final List<dynamic> reportsDyn = (data['reports'] ?? []) as List<dynamic>;
        final reports = reportsDyn.map((e) => e.toString()).toList();

        if (reports.contains(userId)) return false;

        tx.update(ref, {
          'reports': FieldValue.arrayUnion([userId]),
          'reportCount': FieldValue.increment(1),
        });
        return true;
      });
    } catch (e) {
      debugPrint('❌ signalerVideo error: $e');
      return false;
    }
  }

  /// Supprime une vidéo
  Future<bool> deleteVideo(String videoId) async {
    try {
      await videoManager.pauseAll(contextKey);
      await FirebaseFirestore.instance.collection('videos').doc(videoId).delete();
      videoList.removeWhere((v) => v.id == videoId);
      return true;
    } catch (e) {
      debugPrint('❌ deleteVideo error: $e');
      return false;
    }
  }
}
