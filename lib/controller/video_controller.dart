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
import '../videos/data/watched_video_store.dart';
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
  /// Whether the server still has a page the feed has not asked for.
  ///
  /// Observable because the end-of-feed page depends on it and on nothing
  /// else: a plain field flips inside a fetch that may add no video at all,
  /// so the host had no way to learn the feed had ended.
  final hasMoreVideos = true.obs;
  bool _isLoading = false;
  static const int _limit = 10;
  static const int _liveWindowLimit = 30;
  static const int _liveHeadBufferLimit = 12;
  static const int _pendingLiveThumbnailWarmupLimit = 4;
  static const int _thumbnailPrefetchRadius = 2;

  bool get hasMore => hasMoreVideos.value;
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
    } catch (e, st) {
      AppLogger.warning(
        '❌ Feature flag load error: $e',
        source: 'VideoController._initFeatureFlags',
        error: e,
        stackTrace: st,
      );
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

  /// Every video document this session has already been told about.
  ///
  /// "Nouvelle vidéo" has to mean *published since we looked*, and nothing
  /// else. It used to mean "in the live window but not in `videoList`", and
  /// those are not the same set: [_liveWindowLimit] is 30 while a feed page
  /// is [_limit] = 10, so a cold start on adfoot-production — 14 ready
  /// documents on 2026-08-24 — loaded ten and announced the other four as new
  /// before the user had scrolled anywhere. Opening a shared link did the
  /// same, off a feed of a different size, which is where the "1 nouvelle
  /// vidéo" came from.
  ///
  /// Pagination brings those four in on its own. They were never new.
  final Set<String> _knownVideoIds = <String>{};

  void _markVideoIdsKnown(Iterable<Video> videos) {
    for (final video in videos) {
      _knownVideoIds.add(video.id);
    }
  }

  /// Videos deleted through this controller since it was created.
  ///
  /// `deleteVideo` removes the document and this context's copy of it, and
  /// that used to be the whole story. It is not, on a profile: the grid and
  /// the full-screen player read from *two different lists* — the grid from
  /// `ProfileController.videoList`, the player from this one — so a video
  /// deleted from the player stayed in the grid, and the profile's own
  /// pagination handed it straight back to the player with a URL that no
  /// longer resolves.
  ///
  /// The ids are what the other list needs to reconcile, and only the
  /// controller that performed the deletion can supply them.
  final Set<String> _deletedVideoIds = <String>{};

  /// Ids deleted through this controller, for a surface holding its own list.
  Set<String> get deletedVideoIds => Set.unmodifiable(_deletedVideoIds);

  /// Which videos this device has already watched. See [WatchedVideoStore].
  final WatchedVideoStore _watched = WatchedVideoStore.instance;

  /// [videos] with everything unwatched first, in server order, then the
  /// already-watched ones least-recently-seen first.
  ///
  /// The catalogue is bounded — a player may publish ten videos, and
  /// adfoot-production held fourteen in total on 2026-08-24 — so a feed
  /// ordered by publication date alone opens on the same clip every session
  /// until somebody uploads. That is the opposite of what this app is for: a
  /// recruiter's question is "which players have I not seen yet", and the
  /// feed is the answer to it.
  ///
  /// Stable in both halves, so a video never moves for a reason the user
  /// cannot see. Applied only where the feed is (re)built — never while it is
  /// on screen, or the list would reorder under a scrolling thumb.
  List<Video> _watchedAwareOrder(List<Video> videos) {
    if (!enableFeedFetch || videos.length < 2) return videos;
    // Nothing read yet: server order is a correct answer, just a less useful
    // one. Blocking the feed on a preferences read would not be.
    if (!_watched.isLoaded) return videos;

    final unwatched = <Video>[];
    final watched = <Video>[];

    for (final video in videos) {
      if (_watched.hasWatched(video.id)) {
        watched.add(video);
      } else {
        unwatched.add(video);
      }
    }

    // Nothing seen yet: the server order is already the right answer.
    //
    // The reverse is *not* a shortcut. A feed where everything has been
    // watched is the case this ordering matters most in — it decides whether
    // coming back opens on the clip just finished or on the one seen
    // longest ago.
    if (watched.isEmpty) return videos;

    watched.sort((a, b) {
      final left = _watched.watchedAtMs(a.id) ?? 0;
      final right = _watched.watchedAtMs(b.id) ?? 0;
      return left.compareTo(right);
    });

    return [...unwatched, ...watched];
  }

  /// How many videos after [index] this device has not watched yet.
  ///
  /// The feed's supply of *new* material, which is not the same thing as its
  /// length: a recruiter three videos from the end of a list they have
  /// already seen has nothing ahead of them at all. Pagination is driven by
  /// this rather than by distance to the end, so the page that holds the
  /// unseen videos is asked for while there is still something to watch.
  int unwatchedAfter(int index) {
    if (!_watched.isLoaded) return videoList.length - index - 1;

    var count = 0;
    for (var i = index + 1; i < videoList.length; i++) {
      if (!_watched.hasWatched(videoList[i].id)) count++;
    }
    return count;
  }

  /// Forgets what this session knew.
  ///
  /// Only for a genuine clean slate ([refreshVideos]): a reload that keeps
  /// the feed keeps the knowledge, otherwise the reload itself would make
  /// every video look new again.
  void _forgetKnownVideoIds() {
    _knownVideoIds.clear();
  }

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
    unawaited(_watched.ensureLoaded());

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
              } catch (e, st) {
                AppLogger.warning(
                  '❌ listenToVideos merge error: $e',
                  source: 'VideoController.listenToVideos',
                  error: e,
                  stackTrace: st,
                );
              }
            });
          },
          onError: (Object e) {
            // Terminal for the session, and worth being exact about.
            //
            // Unlike the offers, events and chat watches, nothing here is
            // blocked by a stale handle — `listenToVideos` cancels and
            // re-subscribes unconditionally. The problem is that nothing
            // calls it: `onInit` is its only caller, so once this stream
            // errors the feed stops receiving live updates for good. What is
            // left is pull-to-refresh and pagination, which is why this is
            // degradation rather than an outage — and why it went unnoticed.
            //
            // `debug` is dropped outright by AppLogger in a release build, so
            // there was no record of it at all.
            AppLogger.error(
              'video feed stream stopped; this context will receive no '
              'further live updates until the app is restarted',
              source: 'videos/watch',
              error: e,
            );

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
    if (!isRefresh && !hasMoreVideos.value) {
      return false;
    }

    _isLoading = true;
    _fetchLock = Completer<void>();

    try {
      // Read before the ordering needs it, and alongside the network call
      // rather than after it, so it costs nothing on the critical path.
      final watchedLoaded = _watched.ensureLoaded();
      final page = await _videoRepository.fetchReadyVideosPage(
        limit: _limit,
        startAfter: !isRefresh ? _lastCursor : null,
      );
      await watchedLoaded;
      if (page.fetchedCount == 0) {
        hasMoreVideos.value = false;
        return false;
      }

      final fetched = page.videos;
      _releaseSettledLocalState(fetched);
      // A page the user has been handed is not news, whichever order it
      // arrives in relative to the live stream.
      _markVideoIdsKnown(fetched);

      if (isRefresh) {
        _clearPendingLiveHead();
        videoList.assignAll(hydrateAll(_watchedAwareOrder(fetched)));
      } else {
        final currentIds = videoList.map((v) => v.id).toSet();
        final incoming = fetched
            .where((v) => !currentIds.contains(v.id))
            .toList(growable: false);

        if (incoming.isNotEmpty) {
          videoList.assignAll(_appendBelowCurrent(hydrateAll(incoming)));
        }
      }

      if (videoList.isNotEmpty) {
        _prefetchThumbnailsAround(
          currentIndex.value.clamp(0, videoList.length - 1).toInt(),
        );
      }

      _lastCursor = page.cursor;
      if (fetched.length < _limit) hasMoreVideos.value = false;

      return true;
    } catch (e, st) {
      AppLogger.warning(
        'fetchPaginatedVideos error: $e',
        source: 'VideoController.fetchPaginatedVideos',
        error: e,
        stackTrace: st,
      );
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
      // or not — including what this session had been told about, since the
      // feed those ids described no longer exists.
      _forgetKnownVideoIds();
      _localVideoState.clear();
      _lastCursor = null;
      hasMoreVideos.value = true;
      currentIndex.value = -1;
      videoList.clear();
      return await fetchPaginatedVideos(isRefresh: true);
    } catch (e, st) {
      AppLogger.warning(
        '❌ refreshVideos error: $e',
        source: 'VideoController.refreshVideos',
        error: e,
        stackTrace: st,
      );
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
      final watchedLoaded = _watched.ensureLoaded();
      final page = await _videoRepository.fetchReadyVideosPage(limit: _limit);
      await watchedLoaded;
      final fetched = page.videos;
      _releaseSettledLocalState(fetched);
      _markVideoIdsKnown(fetched);

      await videoManager.disposeAllForContext(contextKey);
      _clearPendingLiveHead();
      _lastCursor = page.cursor;
      hasMoreVideos.value = fetched.length >= _limit;

      if (fetched.isEmpty) {
        currentIndex.value = -1;
        videoList.clear();
        return false;
      }

      videoList.assignAll(hydrateAll(_watchedAwareOrder(fetched)));
      currentIndex.value = 0;
      _prefetchThumbnailsAround(0);
      return true;
    } catch (e, st) {
      AppLogger.warning(
        'refreshVideosKeepingFeed error: $e',
        source: 'VideoController.refreshVideosKeepingFeed',
        error: e,
        stackTrace: st,
      );
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

  /// Merges [incoming] into the part of the feed the user has not reached,
  /// and re-orders that part alone.
  ///
  /// Appending a page to the end is why the ordering stopped short of being
  /// useful: the unseen videos of page two landed *below* the watched tail of
  /// page one, so reaching them meant scrolling through everything already
  /// seen. Ordering the whole list instead would move videos the user is
  /// looking at.
  ///
  /// Everything up to and including the current index is frozen, so nothing
  /// can move under a scrolling thumb; everything after it is off screen, and
  /// re-ordering it is invisible by construction.
  List<Video> _appendBelowCurrent(List<Video> incoming) {
    final frozenCount = (currentIndex.value + 1).clamp(0, videoList.length);
    final frozen = videoList.take(frozenCount).toList();
    final tail = <Video>[...videoList.skip(frozenCount), ...incoming];

    return [...frozen, ..._watchedAwareOrder(tail)];
  }

  @visibleForTesting
  List<Video> appendBelowCurrentForTests(List<Video> incoming) =>
      _appendBelowCurrent(incoming);

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
    // Opening a shared link prepends a video fetched by id. It is on screen,
    // so it is known — and so is everything else the caller just handed us.
    _markVideoIdsKnown(videos);
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
      _deletedVideoIds.add(videoId);
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
      final hydrated = hydrateAll(_watchedAwareOrder(incoming));
      videoList.assignAll(hydrated);
      _markVideoIdsKnown(incoming);
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
    _markVideoIdsKnown(incoming);
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

    // Where the feed's own head sits in this batch.
    //
    // The batch is ordered by `updatedAt` descending, exactly like the pages
    // the feed is built from, so everything before that position was
    // published after the newest video the user already has — and everything
    // after it is a video the feed has simply not paged to yet.
    //
    // That distinction is the whole fix. The live window is [_liveWindowLimit]
    // = 30 documents deep while a page is [_limit] = 10, so "in the window
    // and not in `videoList`" announced the four documents beyond page one as
    // "4 nouvelles vidéos" on every cold start against adfoot-production's 14
    // ready videos, and the same arithmetic off a different feed size is what
    // produced the "1 nouvelle vidéo" after opening a shared link.
    var feedHeadRank = incoming.length;
    for (var i = 0; i < incoming.length; i++) {
      if (existingIds.contains(incoming[i].id)) {
        feedHeadRank = i;
        break;
      }
    }

    for (var i = 0; i < incoming.length; i++) {
      final video = incoming[i];
      if (existingIds.contains(video.id)) continue;
      final alreadyBuffered = bufferedById.containsKey(video.id);
      // Never announce the same document twice: a video this session has
      // already been handed — by a page, by a deep link, by an earlier batch
      // — is not news, whatever its rank.
      if (!alreadyBuffered) {
        if (i >= feedHeadRank) continue;
        if (_knownVideoIds.contains(video.id)) continue;
      }
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
