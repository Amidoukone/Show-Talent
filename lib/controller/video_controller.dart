import 'dart:async';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/video.dart';
import '../widgets/video_manager.dart';

class VideoController extends GetxController {
  final String contextKey;

  VideoController({required this.contextKey});

  var videoList = <Video>[].obs;
  var currentIndex = 0.obs;

  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _isLoading = false;
  static const int _limit = 10;

  final VideoManager _videoManager = VideoManager();
  VideoManager get videoManager => _videoManager;

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  Completer<void>? _fetchLock;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _videoSubscription;
  Timer? _streamDebouncer;
  Timer? _indexDebouncer;

  @override
  void onInit() {
    super.onInit();
    // Throttled reaction to index changes
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
    videoManager.disposeAllForContext(contextKey);
    super.onClose();
  }

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
        final incoming = snapshot.docs
            .map((doc) => Video.fromDoc(doc))
            .where((v) => v.videoUrl.isNotEmpty)
            .toList();

        final byId = {for (var v in videoList) v.id: v};
        for (var v in incoming) {
          byId[v.id] = v;
        }
        videoList.value = incoming.map((v) => byId[v.id]!).toList();

        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length >= _limit;
      });
    }, onError: (e) {
      print("Erreur stream vidéos: $e");
    });
  }

  Future<bool> fetchPaginatedVideos({bool isRefresh = false}) async {
    if (_isLoading || !_hasMore || (_fetchLock?.isCompleted == false)) return false;

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

      final newVideos = snap.docs
          .map((d) => Video.fromDoc(d))
          .where((v) => v.videoUrl.isNotEmpty)
          .toList();

      final currentIds = videoList.map((v) => v.id).toSet();
      final uniqueVideos =
          newVideos.where((v) => !currentIds.contains(v.id)).toList();

      if (isRefresh) {
        videoList.assignAll(newVideos);
      } else {
        videoList.addAll(uniqueVideos);
      }

      if (isRefresh && videoList.isNotEmpty) {
        await _setupInitialPlayback();
      }

      _lastDoc = snap.docs.last;
      if (newVideos.length < _limit) _hasMore = false;

      _fetchLock?.complete();
      return true;
    } catch (e) {
      _fetchLock?.completeError(e);
      return false;
    } finally {
      _isLoading = false;
    }
  }

  Future<bool> refreshVideos() async {
    try {
      await videoManager.disposeAllForContext(contextKey);
      _lastDoc = null;
      _hasMore = true;
      videoList.clear();
      return await fetchPaginatedVideos(isRefresh: true);
    } catch (_) {
      return false;
    }
  }

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

    for (int i = 1; i < 5 && i < urls.length; i++) {
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

  /// Méthode protégée pour éviter exécutions concurrentes
  Future<void> _onCurrentIndexChangedThrottled(int index) async {
    if (index < 0 || index >= videoList.length) return;

    final url = videoList[index].videoUrl;
    final urls = videoList.map((v) => v.videoUrl).toList();
    await _processVideoPlaybackChange(urls, index, url);

    if (index >= videoList.length - 2 && hasMore && !_isLoading) {
      unawaited(fetchPaginatedVideos());
    }
  }

  /// Traitement sécurisé du changement de vidéo
  Future<void> _processVideoPlaybackChange(
      List<String> urls, int idx, String activeUrl) async {
    await videoManager.pauseAllExcept(contextKey, activeUrl);
    videoManager.preloadSurrounding(contextKey, urls, idx, activeUrl: activeUrl);

    CachedVideoPlayerPlus? player =
        videoManager.getController(contextKey, activeUrl);
    final ctrl = player?.controller;

    if (ctrl == null || !ctrl.value.isInitialized || ctrl.value.hasError) {
      try {
        player = await videoManager.initializeController(
          contextKey,
          activeUrl,
          autoPlay: false,
          activeUrl: activeUrl,
        );
      } catch (e) {
        print('❌ Error init controller in onIndexChanged: $e');
        return;
      }
    }
  }

  Future<void> pauseAll() async {
    await videoManager.pauseAll(contextKey);
  }

  /// Réutilise ta logique existante (retry, like, share, etc.) sans modification
  Future<DocumentSnapshot<Map<String, dynamic>>> _getWithRetry(
      DocumentReference<Map<String, dynamic>> ref) async {
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

  Future<bool> likeVideo(String videoId, String userId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      final doc = await _getWithRetry(ref);
      if (!doc.exists) return false;

      final data = doc.data()!;
      final likes = List<String>.from(data['likes'] ?? []);

      if (likes.contains(userId)) {
        likes.remove(userId);
      } else {
        likes.add(userId);
      }

      await ref.update({'likes': likes});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> partagerVideo(String videoId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      final doc = await _getWithRetry(ref);
      if (!doc.exists) return false;

      int shareCount = doc.data()?['shareCount'] ?? 0;
      shareCount++;

      await ref.update({'shareCount': shareCount});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> signalerVideo(String videoId, String userId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      final doc = await _getWithRetry(ref);
      if (!doc.exists) return false;

      final data = doc.data()!;
      final reports = List<String>.from(data['reports'] ?? []);
      int reportCount = data['reportCount'] ?? 0;

      if (!reports.contains(userId)) {
        reports.add(userId);
        reportCount++;
        await ref.update({
          'reports': reports,
          'reportCount': reportCount,
        });
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteVideo(String videoId) async {
    try {
      final toDelete = videoList.firstWhereOrNull((v) => v.id == videoId);
      if (toDelete != null) {
        await videoManager.pauseAll(contextKey);
      }

      await FirebaseFirestore.instance.collection('videos').doc(videoId).delete();
      videoList.removeWhere((v) => v.id == videoId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
