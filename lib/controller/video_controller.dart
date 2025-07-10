import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/video.dart';
import '../widgets/video_manager.dart';

class VideoController extends GetxController {
  final String contextKey;

  VideoController({required this.contextKey});

  var videoList = <Video>[].obs;
  var currentIndex = 0.obs;

  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isLoading = false;
  static const int _limit = 10;

  final VideoManager _videoManager = VideoManager();
  VideoManager get videoManager => _videoManager;

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  Completer<void>? _fetchLock;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _videoSubscription;

  @override
  void onInit() {
    super.onInit();
    ever(currentIndex, _onCurrentIndexChanged);
    listenToVideos();
  }

  @override
  void onClose() {
    _videoSubscription?.cancel();
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
      final fetchedVideos = snapshot.docs
          .map((doc) => Video.fromMap(doc.data()))
          .where((v) => v.videoUrl.isNotEmpty)
          .toList();

      videoList.assignAll(fetchedVideos);

      _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMore = snapshot.docs.length >= _limit;
    }, onError: (e) {
      print("Erreur stream vidéos: $e");
    });
  }

  Future<bool> fetchPaginatedVideos({bool isRefresh = false}) async {
    if (_isLoading || !_hasMore || (_fetchLock?.isCompleted == false)) return false;

    _isLoading = true;
    _fetchLock = Completer<void>();

    try {
      var query = FirebaseFirestore.instance
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
          .map((d) => Video.fromMap(d.data()))
          .where((v) => v.videoUrl.isNotEmpty)
          .toList();

      final currentIds = videoList.map((v) => v.id).toSet();
      final uniqueVideos = newVideos.where((v) => !currentIds.contains(v.id)).toList();

      if (isRefresh) {
        videoList.assignAll(uniqueVideos);
      } else {
        videoList.addAll(uniqueVideos);
      }

      final urls = videoList.map((v) => v.videoUrl).toList();

      if (isRefresh && videoList.isNotEmpty) {
        final firstUrl = videoList.first.videoUrl;

        await videoManager.initializeController(contextKey, firstUrl);
        await videoManager.pauseAllExcept(contextKey, firstUrl);
        videoManager.preloadSurrounding(contextKey, urls, 0);

        for (int i = 1; i < 5 && i < videoList.length; i++) {
          unawaited(
            videoManager.initializeController(contextKey, videoList[i].videoUrl, isPreload: true),
          );
        }
      }

      _lastDoc = snap.docs.last;
      if (newVideos.length < _limit) _hasMore = false;

      _fetchLock?.complete();
      return true;
    } catch (e) {
      _fetchLock?.completeError(e);
      rethrow;
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

  Future<void> refreshVideosIfNeeded() async {
    if (videoList.isEmpty) {
      await refreshVideos();
    }
  }

  void _onCurrentIndexChanged(int index) {
    if (index < 0 || index >= videoList.length) return;

    final currentUrl = videoList[index].videoUrl;
    final urls = videoList.map((v) => v.videoUrl).toList();

    videoManager.pauseAllExcept(contextKey, currentUrl);
    videoManager.preloadSurrounding(contextKey, urls, index);

    for (int i = index + 1; i <= index + 3 && i < videoList.length; i++) {
      final url = videoList[i].videoUrl;
      if (!videoManager.hasController(contextKey, url)) {
        unawaited(videoManager.initializeController(contextKey, url, isPreload: true));
      }
    }

    if (index >= videoList.length - 2 && hasMore && !_isLoading) {
      fetchPaginatedVideos();
    }
  }

  Future<void> pauseAll() async {
    await videoManager.pauseAll(contextKey);
  }

  Future<bool> likeVideo(String videoId, String userId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      final doc = await ref.get();
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
      final doc = await ref.get();
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
      final doc = await ref.get();
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
