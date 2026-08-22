import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';

import '../models/action_response.dart';
import '../models/video.dart';
import '../services/feature_flag_service.dart';
import '../services/videos/video_action_service.dart';
import '../services/videos/video_repository.dart';
import '../services/video_observability_service.dart';
import '../utils/video_ui_strings.dart';
import '../videos/video_manager.dart';
import '../screens/success_toast.dart';
import 'user_controller.dart';
import 'package:adfoot/services/app_logger.dart';

class VideoController extends GetxController {
  final String contextKey;
  final bool enableLiveStream;
  final bool enableFeedFetch;

  VideoController({
    required this.contextKey,
    this.enableLiveStream = true,
    bool? enableFeedFetch,
    VideoRepository? videoRepository,
    VideoActionService? videoActionService,
  }) : enableFeedFetch = enableFeedFetch ?? enableLiveStream,
       _videoRepository = videoRepository ?? VideoRepository(),
       _videoActionService = videoActionService ?? VideoActionService();

  final VideoRepository _videoRepository;
  final VideoActionService _videoActionService;

  // ------------------------------------------------------------------
  // UI STATE
  // ------------------------------------------------------------------

  final videoList = <Video>[].obs;
  final currentIndex = 0.obs;
  final pendingLiveCount = 0.obs;

  // ------------------------------------------------------------------
  // PAGINATION
  // ------------------------------------------------------------------

  VideoFeedCursor? _lastCursor;
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
  // FEATURE FLAGS (ADAPTIVE MP4)
  // ------------------------------------------------------------------

  bool _adaptivePlaybackEnabled = false;

  bool get adaptivePlaybackEnabled => _adaptivePlaybackEnabled;

  Future<void> _initFeatureFlags() async {
    try {
      final uid = Get.isRegistered<UserController>()
          ? Get.find<UserController>().user?.uid
          : null;

      final service = FeatureFlagService();
      await service.fetchConfig();

      _adaptivePlaybackEnabled = service.isAdaptiveEnabledForUser(uid);
      _videoManager.updateAdaptiveFlag(_adaptivePlaybackEnabled);
    } catch (e) {
      AppLogger.debug('❌ Feature flag load error: $e');
      _adaptivePlaybackEnabled = false;
      _videoManager.updateAdaptiveFlag(false);
    }
  }

  // ------------------------------------------------------------------
  // BACKEND SERVICES
  // ------------------------------------------------------------------

  final VideoObservabilityService _observability =
      VideoObservabilityService.instance;

  // ------------------------------------------------------------------
  // INTERNAL LOCKS
  // ------------------------------------------------------------------

  Completer<void>? _fetchLock;

  /// Releases the in-flight guard without ever surfacing an error.
  ///
  /// [_fetchLock] is only ever read as a boolean ("is a page already being
  /// fetched?"): nothing awaits its future. Completing it with
  /// `completeError` therefore produced a rejection with no listener — an
  /// unhandled asynchronous error, which `runZonedGuarded` in main() routes
  /// to `AppBootstrap.reportZoneError` and Crashlytics records as **fatal**.
  /// Every feed page that failed for an entirely ordinary reason (offline,
  /// a permission-denied while the session was being revoked) was booked as
  /// a crash, and the failure the user actually saw was drowned in it.
  ///
  /// Completing from a single place also removes the second hazard: the old
  /// code completed inside `try` and completed *again* from `catch` whenever
  /// anything after the first completion threw, which is a StateError.
  void _releaseFetchLock() {
    final lock = _fetchLock;
    if (lock != null && !lock.isCompleted) {
      lock.complete();
    }
  }

  StreamSubscription<VideoLiveBatch>? _videoSubscription;
  Timer? _streamDebouncer;
  final Set<String> _thumbnailPrefetchInFlight = <String>{};
  final Set<String> _thumbnailPrefetched = <String>{};
  final List<Video> _pendingLiveHead = <Video>[];
  Future<void> Function(String thumbUrl)? _thumbnailPrefetchOverride;

  bool _isPermissionDenied(Object error) =>
      VideoRepository.isPermissionDenied(error);

  Future<void> _handleProtectedAccessDenied() async {
    if (!Get.isRegistered<UserController>()) {
      return;
    }

    await Get.find<UserController>().handleProtectedAccessDenied(
      fallbackTitle: VideoUiStrings.protectedAccessTitle,
      fallbackMessage: VideoUiStrings.protectedAccessMessage,
    );
  }

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
    _videoSubscription = _videoRepository
        .watchReadyVideos(limit: _liveWindowLimit)
        .listen(
          (batch) {
            _streamDebouncer?.cancel();
            _streamDebouncer = Timer(const Duration(milliseconds: 120), () {
              try {
                final incoming = batch.videos;

                if (incoming.isEmpty) return;

                final merged = _applyLiveWindow(incoming);
                if (merged.isEmpty) return;

                if (_lastCursor == null && batch.cursor != null) {
                  _lastCursor = batch.cursor;
                }

                final safeIndex = currentIndex.value
                    .clamp(0, merged.length - 1)
                    .toInt();
                _prefetchThumbnailsAround(safeIndex);
              } catch (e) {
                AppLogger.debug('❌ listenToVideos merge error: $e');
              }
            });
          },
          onError: (e) {
            AppLogger.debug('Video stream error: $e');
            if (_isPermissionDenied(e)) {
              unawaited(_handleProtectedAccessDenied());
            }
          },
        );
  }

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
      final page = await _videoRepository.fetchReadyVideosPage(
        limit: _limit,
        startAfter: !isRefresh ? _lastCursor : null,
      );
      if (page.fetchedCount == 0) {
        _hasMore = false;
        return false;
      }

      final fetched = page.videos;
      _releaseSettledLocalState(fetched);

      if (isRefresh) {
        _clearPendingLiveHead();
        videoList.assignAll(hydrateAll(fetched));
      } else {
        final currentIds = videoList.map((v) => v.id).toSet();
        videoList.addAll(
          hydrateAll(fetched.where((v) => !currentIds.contains(v.id))),
        );
      }

      if (videoList.isNotEmpty) {
        _prefetchThumbnailsAround(
          currentIndex.value.clamp(0, videoList.length - 1).toInt(),
        );
      }

      _lastCursor = page.cursor;
      if (fetched.length < _limit) _hasMore = false;

      return true;
    } catch (e) {
      AppLogger.debug('fetchPaginatedVideos error: $e');
      if (_isPermissionDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
      }
      return false;
    } finally {
      _isLoading = false;
      _releaseFetchLock();
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
      // A full refresh is a clean slate: nothing local outlives it, pending
      // or not.
      _localVideoState.clear();
      _lastCursor = null;
      _hasMore = true;
      currentIndex.value = -1;
      videoList.clear();
      return await fetchPaginatedVideos(isRefresh: true);
    } catch (e) {
      AppLogger.debug('❌ refreshVideos error: $e');
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
      final page = await _videoRepository.fetchReadyVideosPage(limit: _limit);
      final fetched = page.videos;
      _releaseSettledLocalState(fetched);

      await videoManager.disposeAllForContext(contextKey);
      _clearPendingLiveHead();
      _lastCursor = page.cursor;
      _hasMore = fetched.length >= _limit;

      if (fetched.isEmpty) {
        currentIndex.value = -1;
        videoList.clear();
        return false;
      }

      videoList.assignAll(hydrateAll(fetched));
      currentIndex.value = 0;
      _prefetchThumbnailsAround(0);
      return true;
    } catch (e) {
      AppLogger.debug('refreshVideosKeepingFeed error: $e');
      if (_isPermissionDenied(e)) {
        unawaited(_handleProtectedAccessDenied());
      }
      return false;
    } finally {
      _isLoading = false;
      _releaseFetchLock();
    }
  }

  Future<void> pauseAll() => videoManager.pauseAll(contextKey);

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
      final safeIndex = currentIndex.value
          .clamp(0, nextFeed.length - 1)
          .toInt();
      _prefetchThumbnailsAround(safeIndex);
    }

    return insertedCount;
  }

  void prefetchThumbnailsAroundIndex(int index) {
    prefetchThumbnailsFor(videoList, index);
  }

  /// Warms the thumbnails around [centerIndex] of the list actually on screen.
  ///
  /// [prefetchThumbnailsAroundIndex] indexes into [videoList], which is only
  /// the right list for the main feed. A search result set and a profile's
  /// videos are different lists of different objects, so pointing the old
  /// method at them either warmed the wrong thumbnails or — as the home
  /// feed's search branch concluded — had to be skipped entirely, and those
  /// surfaces got no prefetching at all.
  void prefetchThumbnailsFor(List<Video> videos, int centerIndex) {
    if (videos.isEmpty) return;
    if (centerIndex < 0 || centerIndex >= videos.length) return;
    _prefetchThumbnailsAround(centerIndex, videos: videos);
  }

  /// Whether reaching [index] should surface the buffered live videos.
  ///
  /// Split out of `updateCurrentIndex` so the pager can own the index and the
  /// host can still answer this question: the answer depends on where the
  /// user came *from*, which is lost the moment the index is written.
  bool shouldSurfacePendingLiveAt({
    required int previousIndex,
    required int index,
  }) {
    return enableLiveStream &&
        previousIndex > 0 &&
        index == 0 &&
        hasPendingLiveVideos;
  }

  void replaceVideos(List<Video> videos, {int? selectedIndex}) {
    _clearPendingLiveHead();
    _releaseSettledLocalState(videos);
    videoList.assignAll(hydrateAll(videos));

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

  // Les actions prennent la vidéo, plus son identifiant seul.
  //
  // Une vidéo affichée n'est pas forcément dans `videoList` : les résultats de
  // recherche et les vidéos d'un profil sont des instances distinctes du même
  // document. Chercher par identifiant dans `videoList` faisait donc échouer
  // silencieusement la mise à jour locale sur toutes ces surfaces — et, pour
  // la suppression, empêchait même de libérer le lecteur natif de la vidéo
  // supprimée, faute de retrouver son URL.
  Future<ActionResponse> likeVideo(Video video, String userId) async {
    final videoId = video.id;
    var response = await _callAction('likeVideo', {
      'videoId': videoId,
    }, offlineMessage: VideoUiStrings.likeOffline);

    if (!response.success && response.code == 'unauthenticated') {
      response = await _likeVideoWithFirestoreFallback(videoId, userId);
    }

    if (response.success) {
      final liked = response.data?['liked'] == true;
      _applyLikeState(video, userId, liked);
    } else {
      unawaited(
        _logActionFailure(
          'likeVideo',
          videoId: videoId,
          code: response.code,
          message: response.message,
        ),
      );
      _restoreFromStreamSoon(videoId);
      response.showToast();
    }

    return response;
  }

  Future<ActionResponse> signalerVideo(Video video, String userId) async {
    final videoId = video.id;
    var response = await _callAction('reportVideo', {
      'videoId': videoId,
    }, offlineMessage: VideoUiStrings.reportOffline);

    if (!response.success && response.code == 'unauthenticated') {
      response = await _reportVideoWithFirestoreFallback(videoId, userId);
    }

    final toastLevel = response.code == 'already_reported'
        ? ToastLevel.info
        : (response.success ? ToastLevel.success : response.toast);

    final resolved = response.copyWith(toast: toastLevel);

    if (resolved.success) {
      _applyReportState(video, userId, resolved.data?['reportCount'] as int?);
    } else {
      unawaited(
        _logActionFailure(
          'reportVideo',
          videoId: videoId,
          code: resolved.code,
          message: resolved.message,
        ),
      );
    }

    resolved.showToast(includeSuccess: true);
    return resolved;
  }

  Future<ActionResponse> deleteVideo(Video video) async {
    final videoId = video.id;
    final response = await _callAction('deleteVideo', {
      'videoId': videoId,
    }, offlineMessage: VideoUiStrings.deleteOffline);

    if (response.success) {
      _localVideoState.remove(videoId);
      final removedIndex = videoList.indexWhere((v) => v.id == videoId);
      // L'URL vient de la vidéo supprimée, pas d'une recherche dans la liste :
      // depuis une recherche ou un profil, elle n'y est pas, et le lecteur
      // natif restait alors alloué sur une vidéo qui n'existe plus.
      final removedUrl = video.videoUrl;

      await videoManager.pauseAll(contextKey);

      if (removedUrl.isNotEmpty) {
        await videoManager.disposeUrls(contextKey, [removedUrl]);
      }

      if (removedIndex != -1) {
        videoList.removeAt(removedIndex);
        if (videoList.isEmpty) {
          currentIndex.value = -1;
        } else {
          final clampedIndex = currentIndex.value
              .clamp(0, videoList.length - 1)
              .toInt();
          currentIndex.value = clampedIndex;
          _prefetchThumbnailsAround(clampedIndex);
        }
        videoList.refresh();
      }

      showSuccessToast(response.message);
    } else {
      unawaited(
        _logActionFailure(
          'deleteVideo',
          videoId: videoId,
          code: response.code,
          message: response.message,
        ),
      );
      response.showToast();
    }

    return response;
  }

  // ------------------------------------------------------------------
  // SHARE (Function + anti-spam)
  // ------------------------------------------------------------------

  Future<ActionResponse> partagerVideo(Video video) async {
    final videoId = video.id;
    var response = await _callAction('shareVideo', {
      'videoId': videoId,
    }, offlineMessage: VideoUiStrings.shareOffline);

    if (!response.success && response.code == 'unauthenticated') {
      response = await _shareVideoWithFirestoreFallback(videoId);
    }

    final resolved = response.code == 'resource-exhausted'
        ? response.copyWith(toast: ToastLevel.info)
        : response;

    if (resolved.success) {
      _applyShareState(video, resolved.data?['shareCount'] as int?);
    } else if (resolved.code != 'resource-exhausted') {
      unawaited(
        _logActionFailure(
          'shareVideo',
          videoId: videoId,
          code: resolved.code,
          message: resolved.message,
        ),
      );
    }

    resolved.showToast();
    return resolved;
  }

  // ------------------------------------------------------------------
  // HELPERS
  // ------------------------------------------------------------------

  Future<ActionResponse> _callAction(
    String functionName,
    Map<String, dynamic> payload, {
    String? offlineMessage,
  }) async {
    final response = await _videoActionService.callAction(
      functionName,
      payload,
      offlineMessage: offlineMessage,
    );
    return _handleProtectedResponse(response);
  }

  Future<ActionResponse> _reportVideoWithFirestoreFallback(
    String videoId,
    String userId,
  ) async {
    final response = await _videoRepository.reportVideoWithFirestoreFallback(
      videoId,
      userId,
    );
    return _handleProtectedResponse(response);
  }

  Future<ActionResponse> _likeVideoWithFirestoreFallback(
    String videoId,
    String userId,
  ) async {
    final response = await _videoRepository.likeVideoWithFirestoreFallback(
      videoId,
      userId,
    );
    return _handleProtectedResponse(response);
  }

  Future<ActionResponse> _shareVideoWithFirestoreFallback(
    String videoId,
  ) async {
    final response = await _videoRepository.shareVideoWithFirestoreFallback(
      videoId,
    );
    return _handleProtectedResponse(response);
  }

  ActionResponse _handleProtectedResponse(ActionResponse response) {
    if (response.code == 'session_revoked') {
      unawaited(_handleProtectedAccessDenied());
    }
    return response;
  }

  // ------------------------------------------------------------------
  // LOCAL VIDEO STATE — the single writer
  // ------------------------------------------------------------------

  /// Local state for videos this controller has acted on, keyed by video id.
  ///
  /// Keyed by id, and not simply written onto the object, because the same
  /// document is a *different instance* on every surface: the feed builds one
  /// from its snapshot, the search builds another from its own query, the
  /// profile a third. In-place mutation only ever reached the instance the
  /// caller happened to be holding, so liking a video in the search results
  /// left the feed's copy of it untouched — and the reverse.
  ///
  /// [_LocalVideoState.pending] is what keeps an optimistic update on screen.
  /// The live Firestore stream pushes a batch whenever *any* video document
  /// changes, so without it a like would visibly snap back to the old count
  /// on the next unrelated snapshot, then jump forward again when the
  /// callable's own write finally arrived.
  final Map<String, _LocalVideoState> _localVideoState =
      <String, _LocalVideoState>{};

  /// The video as it should be shown: the server's document, plus whatever
  /// local state this controller holds for it.
  ///
  /// Call it on any list this controller does not own — search results,
  /// a profile's videos. Entries of [videoList] are already up to date.
  Video hydrate(Video video) => _localVideoState[video.id]?.video ?? video;

  List<Video> hydrateAll(Iterable<Video> videos) => [
    for (final video in videos) hydrate(video),
  ];

  /// Produces and publishes a new state for [video].
  ///
  /// The only place a video's social state changes. [pending] marks an
  /// optimistic value that must survive incoming snapshots until the server
  /// has spoken; a settled value yields to the next server document.
  Video applyLocalVideoState(
    Video video,
    Video Function(Video current) update, {
    required bool pending,
  }) {
    final current = _localVideoState[video.id]?.video ?? video;
    final next = update(current);

    _localVideoState[video.id] = _LocalVideoState(
      video: next,
      pending: pending,
    );

    final idx = videoList.indexWhere((item) => item.id == video.id);
    if (idx != -1) {
      videoList[idx] = next;
    }
    videoList.refresh();

    return next;
  }

  /// Forgets local state for videos the server has just spoken about.
  ///
  /// A settled value has no claim over a fresh document; a pending one does,
  /// until its action reports back.
  void _releaseSettledLocalState(Iterable<Video> incoming) {
    if (_localVideoState.isEmpty) return;

    for (final video in incoming) {
      final local = _localVideoState[video.id];
      if (local != null && !local.pending) {
        _localVideoState.remove(video.id);
      }
    }
  }

  @visibleForTesting
  bool hasPendingLocalStateForTests(String videoId) =>
      _localVideoState[videoId]?.pending ?? false;

  void _applyLikeState(Video video, String userId, bool liked) {
    applyLocalVideoState(
      video,
      (current) => current.withLike(userId, liked: liked),
      pending: false,
    );
  }

  void _applyReportState(Video video, String userId, int? reportCount) {
    applyLocalVideoState(
      video,
      (current) => current.withReport(userId, reportCount: reportCount),
      pending: false,
    );
  }

  void _applyShareState(Video video, int? shareCount) {
    applyLocalVideoState(
      video,
      (current) => current.withShare(shareCount: shareCount),
      pending: false,
    );
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
    await _observability.logActionFailure(
      action: action,
      videoId: videoId,
      code: code,
      message: message,
      metadata: {'contextKey': contextKey, ...?extra},
    );
  }

  List<Video> _applyLiveWindow(List<Video> incoming) {
    _releaseSettledLocalState(incoming);

    final existing = videoList.toList();
    if (existing.isEmpty) {
      _clearPendingLiveHead();
      if (currentIndex.value < 0 || currentIndex.value >= incoming.length) {
        currentIndex.value = 0;
      }
      final hydrated = hydrateAll(incoming);
      videoList.assignAll(hydrated);
      return hydrated;
    }

    final existingIds = existing.map((video) => video.id).toSet();
    final incomingById = {for (final video in incoming) video.id: video};

    // hydrate() is what keeps an optimistic like on screen: this batch fires
    // whenever *any* video document changes, so an unrelated snapshot would
    // otherwise replace the entry the user just tapped with its pre-tap
    // counters, and the heart would visibly flip back and forth.
    final stableFeed = [
      for (final video in existing) hydrate(incomingById[video.id] ?? video),
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

  void _prefetchThumbnailsAround(int centerIndex, {List<Video>? videos}) {
    final source = videos ?? videoList;
    if (source.isEmpty) return;

    final start = (centerIndex - _thumbnailPrefetchRadius)
        .clamp(0, source.length - 1)
        .toInt();
    final end = (centerIndex + _thumbnailPrefetchRadius)
        .clamp(0, source.length - 1)
        .toInt();

    for (int i = start; i <= end; i++) {
      final thumbUrl = source[i].thumbnailUrl.trim();
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

/// One video's locally-held social state.
///
/// [pending] separates "the user just tapped this and the server has not
/// answered yet" from "the server answered and this is what it said". Only
/// the first survives an incoming snapshot; the second yields to it, which is
/// what stops local state from outliving the truth.
class _LocalVideoState {
  const _LocalVideoState({required this.video, required this.pending});

  final Video video;
  final bool pending;
}
