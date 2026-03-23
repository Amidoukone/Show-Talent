import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';

import '../models/action_response.dart';
import '../models/video.dart';
import '../services/feature_flag_service.dart';
import '../widgets/video_manager.dart';
import '../screens/success_toast.dart';
import 'user_controller.dart';

class VideoController extends GetxController {
  final String contextKey;
  final bool enableLiveStream;
  final bool enableFeedFetch;

  VideoController({
    required this.contextKey,
    this.enableLiveStream = true,
    bool? enableFeedFetch,
  }) : enableFeedFetch = enableFeedFetch ?? enableLiveStream;

  // ------------------------------------------------------------------
  // UI STATE
  // ------------------------------------------------------------------

  final videoList = <Video>[].obs;
  final currentIndex = 0.obs;
  final pendingLiveCount = 0.obs;

  // ------------------------------------------------------------------
  // PAGINATION
  // ------------------------------------------------------------------

  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _isLoading = false;
  static const int _limit = 10;
  static const int _liveWindowLimit = 30;
  static const int _liveHeadBufferLimit = 12;
  static const int _pendingLiveThumbnailWarmupLimit = 4;
  static const int _thumbnailPrefetchRadius = 2;

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;
  bool get hasPendingLiveVideos => pendingLiveCount.value > 0;

  // ------------------------------------------------------------------
  // VIDEO MANAGER
  // ------------------------------------------------------------------

  final VideoManager _videoManager = VideoManager();
  VideoManager get videoManager => _videoManager;

  // ------------------------------------------------------------------
  // FEATURE FLAGS (ADAPTIVE / HLS)
  // ------------------------------------------------------------------

  bool _adaptivePlaybackEnabled = false;
  bool _hlsPlaybackEnabled = false;
  bool _preferHlsPlayback = false;

  bool get adaptivePlaybackEnabled => _adaptivePlaybackEnabled;
  bool get hlsPlaybackEnabled => _hlsPlaybackEnabled;
  bool get preferHlsPlayback => _preferHlsPlayback;

  Future<void> _initFeatureFlags() async {
    try {
      final uid = Get.isRegistered<UserController>()
          ? Get.find<UserController>().user?.uid
          : null;

      final service = FeatureFlagService();
      await service.fetchConfig();

      _adaptivePlaybackEnabled = service.isAdaptiveEnabledForUser(uid);
      _hlsPlaybackEnabled = service.isHlsPlaybackEnabledForUser(uid);
      _preferHlsPlayback = service.shouldPreferHlsForUser(uid);

      _videoManager.updateAdaptiveFlag(_adaptivePlaybackEnabled);
      _videoManager.updateHlsStrategyFlag(_preferHlsPlayback);
    } catch (e) {
      debugPrint('❌ Feature flag load error: $e');
      _adaptivePlaybackEnabled = false;
      _hlsPlaybackEnabled = false;
      _preferHlsPlayback = false;
      _videoManager.updateAdaptiveFlag(false);
      _videoManager.updateHlsStrategyFlag(false);
    }
  }

  // ------------------------------------------------------------------
  // CLOUD FUNCTIONS / CONNECTIVITY
  // ------------------------------------------------------------------

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');
  final Connectivity _connectivity = Connectivity();

  // ------------------------------------------------------------------
  // INTERNAL LOCKS
  // ------------------------------------------------------------------

  Completer<void>? _fetchLock;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _videoSubscription;
  Timer? _streamDebouncer;
  final Set<String> _thumbnailPrefetchInFlight = <String>{};
  final Set<String> _thumbnailPrefetched = <String>{};
  final List<Video> _pendingLiveHead = <Video>[];
  Future<void> Function(String thumbUrl)? _thumbnailPrefetchOverride;

  // ------------------------------------------------------------------
  // LIFECYCLE
  // ------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();

    _videoManager.updateAdaptiveFlag(false);
    unawaited(_initFeatureFlags());

    if (enableLiveStream) {
      listenToVideos();
    }
  }

  @override
  void onClose() {
    _streamDebouncer?.cancel();
    _videoSubscription?.cancel();
    unawaited(videoManager.disposeAllForContext(contextKey));
    super.onClose();
  }

  // ------------------------------------------------------------------
  // FIRESTORE STREAM (LIVE)
  // ------------------------------------------------------------------

  void listenToVideos() {
    _videoSubscription?.cancel();
    _videoSubscription = FirebaseFirestore.instance
        .collection('videos')
        .where('status', isEqualTo: 'ready')
        .orderBy('updatedAt', descending: true)
        .limit(_liveWindowLimit)
        .snapshots()
        .listen((snapshot) {
      _streamDebouncer?.cancel();
      _streamDebouncer = Timer(const Duration(milliseconds: 120), () {
        try {
          final incoming = snapshot.docs
              .map(Video.fromDoc)
              .where((v) => v.videoUrl.isNotEmpty)
              .toList();

          if (incoming.isEmpty) return;

          final merged = _applyLiveWindow(incoming);
          if (merged.isEmpty) return;

          if (_lastDoc == null && snapshot.docs.isNotEmpty) {
            _lastDoc = snapshot.docs.last;
          }

          final safeIndex =
              currentIndex.value.clamp(0, merged.length - 1).toInt();
          _prefetchThumbnailsAround(safeIndex);
        } catch (e) {
          debugPrint('❌ listenToVideos merge error: $e');
        }
      });
    }, onError: (e) {
      debugPrint('❌ Erreur stream vidéos: $e');
    });
  }

  // ------------------------------------------------------------------
  // PAGINATED FETCH
  // ------------------------------------------------------------------

  Future<bool> fetchPaginatedVideos({bool isRefresh = false}) async {
    if (!enableFeedFetch) {
      return false;
    }
    if (_isLoading || (_fetchLock?.isCompleted == false)) {
      return false;
    }
    if (!isRefresh && !_hasMore) {
      return false;
    }

    _isLoading = true;
    _fetchLock = Completer<void>();

    try {
      final snap = await _loadReadyVideosPage(
        startAfter: !isRefresh ? _lastDoc : null,
      );
      if (snap.docs.isEmpty) {
        _hasMore = false;
        _fetchLock?.complete();
        return false;
      }

      final fetched = snap.docs
          .map(Video.fromDoc)
          .where((v) => v.videoUrl.isNotEmpty)
          .toList();

      if (isRefresh) {
        _clearPendingLiveHead();
        videoList.assignAll(fetched);
      } else {
        final currentIds = videoList.map((v) => v.id).toSet();
        videoList.addAll(
          fetched.where((v) => !currentIds.contains(v.id)),
        );
      }

      if (videoList.isNotEmpty) {
        _prefetchThumbnailsAround(
          currentIndex.value.clamp(0, videoList.length - 1).toInt(),
        );
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

  // ------------------------------------------------------------------
  // FULL REFRESH
  // ------------------------------------------------------------------

  Future<bool> refreshVideos() async {
    if (!enableFeedFetch) {
      return false;
    }
    try {
      await videoManager.disposeAllForContext(contextKey);
      _clearPendingLiveHead();
      _lastDoc = null;
      _hasMore = true;
      currentIndex.value = -1;
      videoList.clear();
      return await fetchPaginatedVideos(isRefresh: true);
    } catch (e) {
      debugPrint('❌ refreshVideos error: $e');
      return false;
    }
  }

  Future<bool> refreshVideosKeepingFeed() async {
    if (!enableFeedFetch) {
      return false;
    }
    if (_isLoading || (_fetchLock?.isCompleted == false)) {
      return false;
    }

    _isLoading = true;
    _fetchLock = Completer<void>();

    try {
      final snap = await _loadReadyVideosPage();
      final fetched = snap.docs
          .map(Video.fromDoc)
          .where((v) => v.videoUrl.isNotEmpty)
          .toList();

      await videoManager.disposeAllForContext(contextKey);
      _clearPendingLiveHead();
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMore = fetched.length >= _limit;

      if (fetched.isEmpty) {
        currentIndex.value = -1;
        videoList.clear();
        _fetchLock?.complete();
        return false;
      }

      videoList.assignAll(fetched);
      currentIndex.value = 0;
      _prefetchThumbnailsAround(0);
      _fetchLock?.complete();
      return true;
    } catch (e) {
      debugPrint('refreshVideosKeepingFeed error: $e');
      _fetchLock?.completeError(e);
      return false;
    } finally {
      _isLoading = false;
    }
  }

  Future<void> pauseAll() => videoManager.pauseAll(contextKey);

  bool updateCurrentIndex(int index) {
    final previousIndex = currentIndex.value;
    currentIndex.value = index;

    return enableLiveStream &&
        previousIndex > 0 &&
        index == 0 &&
        hasPendingLiveVideos;
  }

  int applyBufferedLiveVideos({bool moveToTop = false}) {
    if (_pendingLiveHead.isEmpty) {
      if (moveToTop && videoList.isNotEmpty) {
        currentIndex.value = 0;
      }
      return 0;
    }

    final nextFeed = _prependUnique(_pendingLiveHead, videoList);
    final insertedCount = nextFeed.length - videoList.length;
    videoList.assignAll(nextFeed);
    _clearPendingLiveHead();

    if (nextFeed.isEmpty) {
      currentIndex.value = -1;
      return insertedCount;
    }

    if (moveToTop) {
      currentIndex.value = 0;
      _prefetchThumbnailsAround(0);
    } else {
      final safeIndex =
          currentIndex.value.clamp(0, nextFeed.length - 1).toInt();
      _prefetchThumbnailsAround(safeIndex);
    }

    return insertedCount;
  }

  void prefetchThumbnailsAroundIndex(int index) {
    if (videoList.isEmpty) return;
    if (index < 0 || index >= videoList.length) return;
    _prefetchThumbnailsAround(index);
  }

  void replaceVideos(
    List<Video> videos, {
    int? selectedIndex,
  }) {
    _clearPendingLiveHead();
    videoList.assignAll(videos);

    if (videos.isEmpty) {
      currentIndex.value = -1;
      return;
    }

    final nextIndex = (selectedIndex ?? currentIndex.value)
        .clamp(0, videos.length - 1)
        .toInt();
    currentIndex.value = nextIndex;
    _prefetchThumbnailsAround(nextIndex);
  }

  // ------------------------------------------------------------------
  // ACTIONS VIA CLOUD FUNCTIONS
  // ------------------------------------------------------------------

  Future<ActionResponse> likeVideo(String videoId, String userId) async {
    final response = await _callAction(
      'likeVideo',
      {'videoId': videoId},
      offlineMessage: 'Impossible de liker hors connexion.',
    );

    if (response.success) {
      final liked = response.data?['liked'] == true;
      _applyLikeState(videoId, userId, liked);
    } else {
      unawaited(_logActionFailure(
        'likeVideo',
        videoId: videoId,
        code: response.code,
        message: response.message,
      ));
      _restoreFromStreamSoon(videoId);
      response.showToast();
    }

    return response;
  }

  Future<ActionResponse> signalerVideo(String videoId, String userId) async {
    final response = await _callAction(
      'reportVideo',
      {'videoId': videoId},
      offlineMessage: 'Connexion requise pour signaler.',
    );

    final toastLevel = response.code == 'already_reported'
        ? ToastLevel.info
        : (response.success ? ToastLevel.success : ToastLevel.error);

    final resolved = response.copyWith(toast: toastLevel);

    if (resolved.success) {
      _applyReportState(
        videoId,
        userId,
        resolved.data?['reportCount'] as int?,
      );
    } else {
      unawaited(_logActionFailure(
        'reportVideo',
        videoId: videoId,
        code: resolved.code,
        message: resolved.message,
      ));
    }

    resolved.showToast(includeSuccess: true);
    return resolved;
  }

  Future<ActionResponse> deleteVideo(String videoId) async {
    final response = await _callAction(
      'deleteVideo',
      {'videoId': videoId},
      offlineMessage: 'Connexion requise pour supprimer cette vidéo.',
    );

    if (response.success) {
      await videoManager.pauseAll(contextKey);
      videoList.removeWhere((v) => v.id == videoId);
      videoList.refresh();
      showSuccessToast(response.message);
    } else {
      unawaited(_logActionFailure(
        'deleteVideo',
        videoId: videoId,
        code: response.code,
        message: response.message,
      ));
      response.showToast();
    }

    return response;
  }

  // ------------------------------------------------------------------
  // SHARE (Function + anti-spam)
  // ------------------------------------------------------------------

  Future<ActionResponse> partagerVideo(String videoId) async {
    final response = await _callAction(
      'shareVideo',
      {'videoId': videoId},
      offlineMessage: 'Connexion requise pour partager.',
    );

    if (response.success) {
      _applyShareState(
        videoId,
        response.data?['shareCount'] as int?,
      );
    } else {
      unawaited(_logActionFailure(
        'shareVideo',
        videoId: videoId,
        code: response.code,
        message: response.message,
      ));
    }

    response.showToast();
    return response;
  }

  // ------------------------------------------------------------------
  // HELPERS
  // ------------------------------------------------------------------

  Future<ActionResponse> _callAction(
    String functionName,
    Map<String, dynamic> payload, {
    String? offlineMessage,
  }) async {
    try {
      if (await _isOffline()) {
        return ActionResponse.offline(offlineMessage);
      }

      final callable = _functions.httpsCallable(
        functionName,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 10),
        ),
      );

      final result = await callable.call<Map<String, dynamic>>(payload);
      return ActionResponse.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      return ActionResponse.failure(
        message: e.message ?? 'Action impossible.',
        code: e.code,
        retriable: e.code == 'unavailable',
      );
    } catch (e) {
      return ActionResponse.failure(
        message: 'Action impossible pour le moment.',
        retriable: true,
      );
    }
  }

  Future<bool> _isOffline() async {
    try {
      final dynamic res = await _connectivity.checkConnectivity();
      if (res is ConnectivityResult) {
        return res == ConnectivityResult.none;
      }
      if (res is List<ConnectivityResult>) {
        return res.every((r) => r == ConnectivityResult.none);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _applyLikeState(String videoId, String userId, bool liked) {
    final idx = videoList.indexWhere((v) => v.id == videoId);
    if (idx == -1) return;

    final video = videoList[idx];
    video.likes.remove(userId);
    if (liked) video.likes.add(userId);

    videoList[idx] = video;
    videoList.refresh();
  }

  void _applyReportState(
    String videoId,
    String userId,
    int? reportCount,
  ) {
    final idx = videoList.indexWhere((v) => v.id == videoId);
    if (idx == -1) return;

    final video = videoList[idx];
    if (!video.reports.contains(userId)) {
      video.reports.add(userId);
    }
    if (reportCount != null) {
      video.reportCount = reportCount;
    }

    videoList[idx] = video;
    videoList.refresh();
  }

  void _applyShareState(String videoId, int? shareCount) {
    final idx = videoList.indexWhere((v) => v.id == videoId);
    if (idx == -1) return;

    final video = videoList[idx];
    video.shareCount = shareCount ?? (video.shareCount + 1);

    videoList[idx] = video;
    videoList.refresh();
  }

  void _restoreFromStreamSoon(String videoId) {
    Future.delayed(const Duration(milliseconds: 400), () {
      final idx = videoList.indexWhere((v) => v.id == videoId);
      if (idx != -1) videoList.refresh();
    });
  }

  Future<void> _logActionFailure(
    String action, {
    String? videoId,
    String? code,
    String? message,
    Map<String, dynamic>? extra,
  }) async {
    try {
      if (await _isOffline()) return;

      final callable = _functions.httpsCallable(
        'videoActionLog',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 6),
        ),
      );

      await callable.call({
        'action': action,
        'videoId': videoId,
        'code': code,
        'message': message,
        'extra': extra ?? {},
        'platform': kIsWeb ? 'web' : 'mobile',
      });
    } catch (_) {}
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadReadyVideosPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('videos')
        .where('status', isEqualTo: 'ready')
        .orderBy('updatedAt', descending: true)
        .limit(_limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    return query.get();
  }

  List<Video> _applyLiveWindow(List<Video> incoming) {
    final existing = videoList.toList();
    if (existing.isEmpty) {
      _clearPendingLiveHead();
      videoList.assignAll(incoming);
      return incoming;
    }

    final existingIds = existing.map((video) => video.id).toSet();
    final incomingById = {for (final video in incoming) video.id: video};

    final stableFeed = [
      for (final video in existing) incomingById[video.id] ?? video,
    ];

    final nextPendingHead = _buildPendingLiveHead(
      incoming: incoming,
      existingIds: existingIds,
    );

    _replacePendingLiveHead(nextPendingHead);
    videoList.assignAll(stableFeed);
    return stableFeed;
  }

  List<Video> _buildPendingLiveHead({
    required List<Video> incoming,
    required Set<String> existingIds,
  }) {
    if (incoming.isEmpty && _pendingLiveHead.isEmpty) {
      return const [];
    }

    final bufferedById = {
      for (final video in _pendingLiveHead)
        if (!existingIds.contains(video.id)) video.id: video,
    };

    for (final video in incoming) {
      if (existingIds.contains(video.id)) continue;
      bufferedById[video.id] = video;
    }

    final ordered = <Video>[];
    final seen = <String>{};

    void append(Video video) {
      if (existingIds.contains(video.id)) return;
      final buffered = bufferedById[video.id];
      if (buffered == null || !seen.add(video.id)) return;
      ordered.add(buffered);
    }

    for (final video in incoming) {
      append(video);
      if (ordered.length >= _liveHeadBufferLimit) {
        return ordered;
      }
    }

    for (final video in _pendingLiveHead) {
      append(video);
      if (ordered.length >= _liveHeadBufferLimit) {
        break;
      }
    }

    return ordered;
  }

  List<Video> _prependUnique(Iterable<Video> head, Iterable<Video> tail) {
    final merged = <Video>[];
    final seen = <String>{};

    for (final video in head) {
      if (seen.add(video.id)) {
        merged.add(video);
      }
    }

    for (final video in tail) {
      if (seen.add(video.id)) {
        merged.add(video);
      }
    }

    return merged;
  }

  void _replacePendingLiveHead(List<Video> videos) {
    _pendingLiveHead
      ..clear()
      ..addAll(videos);
    pendingLiveCount.value = _pendingLiveHead.length;
    _warmPendingLiveHeadThumbnails(videos);
  }

  void _clearPendingLiveHead() {
    if (_pendingLiveHead.isEmpty && pendingLiveCount.value == 0) {
      return;
    }
    _pendingLiveHead.clear();
    pendingLiveCount.value = 0;
  }

  @visibleForTesting
  List<Video> applyLiveWindowForTests(List<Video> incoming) {
    return _applyLiveWindow(incoming);
  }

  @visibleForTesting
  void setThumbnailPrefetcherForTests(
    Future<void> Function(String thumbUrl)? prefetcher,
  ) {
    _thumbnailPrefetchOverride = prefetcher;
    _thumbnailPrefetchInFlight.clear();
    _thumbnailPrefetched.clear();
  }

  void _prefetchThumbnailsAround(int centerIndex) {
    if (videoList.isEmpty) return;

    final start = (centerIndex - _thumbnailPrefetchRadius)
        .clamp(0, videoList.length - 1)
        .toInt();
    final end = (centerIndex + _thumbnailPrefetchRadius)
        .clamp(0, videoList.length - 1)
        .toInt();

    for (int i = start; i <= end; i++) {
      final thumbUrl = videoList[i].thumbnailUrl.trim();
      if (_shouldSkipThumbnailPrefetch(thumbUrl)) {
        continue;
      }

      _thumbnailPrefetchInFlight.add(thumbUrl);
      unawaited(_prefetchThumbnail(thumbUrl));
    }
  }

  void _warmPendingLiveHeadThumbnails(List<Video> videos) {
    for (final video in videos.take(_pendingLiveThumbnailWarmupLimit)) {
      final thumbUrl = video.thumbnailUrl.trim();
      if (_shouldSkipThumbnailPrefetch(thumbUrl)) {
        continue;
      }

      _thumbnailPrefetchInFlight.add(thumbUrl);
      unawaited(_prefetchThumbnail(thumbUrl));
    }
  }

  bool _shouldSkipThumbnailPrefetch(String thumbUrl) {
    return thumbUrl.isEmpty ||
        _thumbnailPrefetched.contains(thumbUrl) ||
        _thumbnailPrefetchInFlight.contains(thumbUrl);
  }

  Future<void> _prefetchThumbnail(String thumbUrl) async {
    try {
      final prefetcher = _thumbnailPrefetchOverride;
      if (prefetcher != null) {
        await prefetcher(thumbUrl);
      } else {
        await DefaultCacheManager().downloadFile(thumbUrl);
      }
      _thumbnailPrefetched.add(thumbUrl);
    } catch (_) {
      // Best-effort only.
    } finally {
      _thumbnailPrefetchInFlight.remove(thumbUrl);
    }
  }
}
