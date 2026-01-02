import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/action_response.dart';
import '../models/video.dart';
import '../services/feature_flag_service.dart';
import '../widgets/video_manager.dart';
import '../screens/success_toast.dart';
import 'user_controller.dart';

class VideoController extends GetxController {
  final String contextKey;

  VideoController({required this.contextKey});

  // ------------------------------------------------------------------
  //                            UI STATE
  // ------------------------------------------------------------------

  final videoList = <Video>[].obs;
  final currentIndex = 0.obs;

  // ------------------------------------------------------------------
  //                          PAGINATION
  // ------------------------------------------------------------------

  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _isLoading = false;
  static const int _limit = 10;

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  // ------------------------------------------------------------------
  //                       VIDEO MANAGER
  // ------------------------------------------------------------------

  final VideoManager _videoManager = VideoManager();
  VideoManager get videoManager => _videoManager;

  // ------------------------------------------------------------------
  //                    FEATURE FLAGS (ADAPTIVE / HLS)
  // ------------------------------------------------------------------

  bool _adaptivePlaybackEnabled = false;
  bool _hlsPlaybackEnabled = false;

  bool get adaptivePlaybackEnabled => _adaptivePlaybackEnabled;
  bool get hlsPlaybackEnabled => _hlsPlaybackEnabled;

  Future<void> _initFeatureFlags() async {
    try {
      final uid = Get.isRegistered<UserController>()
          ? Get.find<UserController>().user?.uid
          : null;

      final service = FeatureFlagService();
      await service.fetchConfig();

      _adaptivePlaybackEnabled = service.isEnabledForUser(uid);
      _hlsPlaybackEnabled = service.useHlsForUser(uid);

      _videoManager.updateAdaptiveFlag(_adaptivePlaybackEnabled);
    } catch (e) {
      debugPrint('❌ Feature flag load error: $e');
      _adaptivePlaybackEnabled = false;
      _hlsPlaybackEnabled = false;
      _videoManager.updateAdaptiveFlag(false);
    }
  }

  // ------------------------------------------------------------------
  //                 CLOUD FUNCTIONS / CONNECTIVITY
  // ------------------------------------------------------------------

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');
  final Connectivity _connectivity = Connectivity();

  // ------------------------------------------------------------------
  //                       INTERNAL LOCKS
  // ------------------------------------------------------------------

  Completer<void>? _fetchLock;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _videoSubscription;
  Timer? _streamDebouncer;
  Timer? _indexDebouncer;

  // ------------------------------------------------------------------
  //                           LIFECYCLE
  // ------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();

    unawaited(_initFeatureFlags());

    ever<int>(currentIndex, (idx) {
      _indexDebouncer?.cancel();
      _indexDebouncer = Timer(
        const Duration(milliseconds: 200),
        () => _onCurrentIndexChangedThrottled(idx),
      );
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

  // ------------------------------------------------------------------
  //                     FIRESTORE STREAM (LIVE)
  // ------------------------------------------------------------------

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
              .map(Video.fromDoc)
              .where((v) => v.videoUrl.isNotEmpty)
              .toList();

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

  // ------------------------------------------------------------------
  //                        PAGINATED FETCH
  // ------------------------------------------------------------------

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
          .map(Video.fromDoc)
          .where((v) => v.videoUrl.isNotEmpty)
          .toList();

      if (isRefresh) {
        videoList.assignAll(fetched);
      } else {
        final currentIds = videoList.map((v) => v.id).toSet();
        videoList.addAll(
          fetched.where((v) => !currentIds.contains(v.id)),
        );
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

  // ------------------------------------------------------------------
  //                         FULL REFRESH (RESTORED ✅)
  // ------------------------------------------------------------------

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

  // ------------------------------------------------------------------
  //                   INITIAL PLAYBACK SETUP
  // ------------------------------------------------------------------

  Future<void> _setupInitialPlayback() async {
    if (videoList.isEmpty) return;

    currentIndex.value = 0;
    final videos = videoList.toList();
    final first = videos.first;
    final firstUrl = first.videoUrl;

    await videoManager.disposeAllForContext(contextKey);

    await videoManager.initializeController(
      contextKey,
      firstUrl,
      sources: first.sources,
      useHls: _hlsPlaybackEnabled && first.hasHlsSource,
      autoPlay: true,
      activeUrl: firstUrl,
    );

    await videoManager.pauseAllExcept(contextKey, firstUrl);

    videoManager.preloadSurrounding(
      contextKey,
      videos,
      0,
      activeUrl: firstUrl,
      useHls: _hlsPlaybackEnabled,
    );
  }

  // ------------------------------------------------------------------
  //                  INDEX CHANGE (THROTTLED)
  // ------------------------------------------------------------------

  Future<void> _onCurrentIndexChangedThrottled(int index) async {
    final videos = videoList.toList();
    if (index < 0 || index >= videos.length) return;

    final activeVideo = videos[index];
    final activeUrl = activeVideo.videoUrl;

    await videoManager.pauseAllExcept(contextKey, activeUrl);

    videoManager.preloadSurrounding(
      contextKey,
      videos,
      index,
      activeUrl: activeUrl,
      useHls: _hlsPlaybackEnabled,
    );

    if (index >= videoList.length - 2 && hasMore && !_isLoading) {
      unawaited(fetchPaginatedVideos());
    }
  }

  Future<void> pauseAll() => videoManager.pauseAll(contextKey);

  // ------------------------------------------------------------------
  //                  ACTIONS VIA CLOUD FUNCTIONS
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
      response.showToast();
    }

    return response;
  }

  // ------------------------------------------------------------------
  //               SHARE (RESTORED – Firestore direct ✅)
  // ------------------------------------------------------------------

  Future<bool> partagerVideo(String videoId) async {
    try {
      await FirebaseFirestore.instance
          .collection('videos')
          .doc(videoId)
          .update({'shareCount': FieldValue.increment(1)});
      return true;
    } catch (e) {
      debugPrint('❌ partagerVideo error: $e');
      return false;
    }
  }

  // ------------------------------------------------------------------
  //                          HELPERS
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
      debugPrint('❌ $functionName error: ${e.code} ${e.message}');
      return ActionResponse.failure(
        message: e.message ?? 'Action impossible.',
        code: e.code,
        retriable: e.code == 'unavailable',
      );
    } catch (e) {
      debugPrint('❌ $functionName unknown error: $e');
      return ActionResponse.failure(
        message: 'Action impossible pour le moment.',
        retriable: true,
      );
    }
  }

  Future<bool> _isOffline() async {
    try {
      final res = await _connectivity.checkConnectivity();
      return res.contains(ConnectivityResult.none);
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

  void _restoreFromStreamSoon(String videoId) {
    Future.delayed(const Duration(milliseconds: 400), () {
      final idx = videoList.indexWhere((v) => v.id == videoId);
      if (idx != -1) videoList.refresh();
    });
  }
}
