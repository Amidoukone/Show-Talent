import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/video_observability_service.dart';
import 'package:adfoot/services/videos/data/upload_client.dart';
import 'package:adfoot/services/videos/upload_video_error_mapper.dart';
import 'package:adfoot/services/videos/upload_video_repository.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/utils/video_tools.dart';
import 'package:adfoot/screens/success_toast.dart';
import 'package:adfoot/services/app_logger.dart';

/// Distinguishes which upload stage threw, so observability isn't flattened
/// to a single generic "upload-error" code for four operationally very
/// different failures (video transfer / missing thumbnail / thumbnail
/// transfer / finalize).
class _UploadStageException implements Exception {
  const _UploadStageException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class UploadVideoController extends GetxController {
  // How long the upload screen keeps watching before it hands the user back
  // to the feed with the "still processing" message.
  //
  // This was 45s, which was shorter than the work it was waiting for:
  // optimizeMp4Video measured ~1m02 to ~1m24 warm and 4m14 on a cold
  // instance, so the wait effectively always expired. Every successful upload
  // ended on "optimisation en cours" and the video then disappeared — the
  // profile only listed `status == 'ready'` videos, and the optimizer leaves
  // them on `under_review` until an admin approves.
  //
  // 2 minutes covers the warm path with margin, so the common case now ends
  // on the real outcome ("soumise à la revue") instead of a timeout. The cold
  // path still expires, and that is fine: the profile grid now shows the
  // video with its lifecycle badge, and admin approval sends a push
  // (notifyVideoOwner in functions/src/admin_content_actions.ts). Raising
  // this further would only trade an honest hand-off for a longer spinner.
  static const Duration _optimizationOverallTimeout = Duration(seconds: 120);
  static const Duration _pollInterval = Duration(seconds: 10);
  // A cold createUploadSession Cloud Function instance plus a fresh Play
  // Integrity attestation can legitimately take longer than a few seconds on
  // real devices/networks. The ceiling is read from UploadClient rather than
  // written here as a constant: a flat 125s sat *below* that layer's own
  // retry budget, so the controller aborted sessions the last retry would
  // have completed -- and production logged the result as
  // `session-creation-timeout` on an upload whose session the server had in
  // fact just created.
  Duration get _sessionCreationTimeout => _uploadClient.sessionCreationBudget;

  final isUploading = false.obs;
  final isOptimizing = false.obs;
  final isPreparing = false.obs;
  final uploadProgress = 0.0.obs;
  final uploadStage = ''.obs;

  UploadVideoController({
    UploadClient? uploadClient,
    VideoObservabilityService? observability,
    UploadVideoRepository? uploadRepository,
    AuthSessionService? authSessionService,
  }) : _uploadClient = uploadClient ?? UploadClient(),
       _observability = observability ?? VideoObservabilityService.instance,
       _uploadRepository = uploadRepository ?? UploadVideoRepository(),
       _authSessionService = authSessionService ?? AuthSessionService();

  File? selectedVideo;
  File? thumbnail;
  String? description;
  String? caption;
  String? originalVideoPath;

  final UploadClient _uploadClient;
  final VideoObservabilityService _observability;
  final UploadVideoRepository _uploadRepository;
  final AuthSessionService _authSessionService;
  CancelToken? _cancelToken;

  UploadSessionState? _activeSession;
  String? _lastUploadedThumbPath;
  int _operationSerial = 0;
  int? _preparedDurationSec;
  int? _preparedWidth;
  int? _preparedHeight;
  int? _preparedFileSizeBytes;

  @override
  void onClose() {
    _cancelOptimizationWatch?.call();
    _cancelOptimizationWatch = null;
    VideoTools.dispose();
    super.onClose();
  }

  bool _isCurrentOperation(int operation) => operation == _operationSerial;

  /* -------------------------------------------------------------------------- */
  /* Préparation                                                               */
  /* -------------------------------------------------------------------------- */

  Future<bool> prepareUpload({
    required String description,
    required String cap,
    required String videoPath,
  }) async {
    if (isPreparing.value || isUploading.value || isOptimizing.value) {
      return false;
    }

    // A previous attempt may have uploaded the video/thumbnail bytes but
    // failed before finalizing (network blip on finalizeUpload, etc.).
    // uploadDirectly() always resets state on failure, and this fresh
    // prepareUpload call is about to create a brand-new session/storage
    // path (a new temp file for trimmed videos never matches the old
    // session's localFilePath) -- so the previous attempt's bytes would
    // otherwise sit orphaned in Cloud Storage forever. Clean them up first.
    await _cleanupOrphanedSession();

    final sanitizedDescription = description.trim();
    final sanitizedCaption = cap.trim();
    final operation = ++_operationSerial;

    if (sanitizedDescription.isEmpty || sanitizedCaption.isEmpty) {
      showErrorToast(VideoUiStrings.uploadMissingRequiredFields);
      return false;
    }

    isPreparing(true);
    uploadProgress.value = 0.0;
    uploadStage.value = '';
    selectedVideo = null;
    thumbnail = null;
    this.description = null;
    caption = null;
    originalVideoPath = null;
    _preparedDurationSec = null;
    _preparedWidth = null;
    _preparedHeight = null;
    _preparedFileSizeBytes = null;

    var isPrepared = false;

    try {
      final sourceFile = File(videoPath);
      if (!await sourceFile.exists()) {
        showErrorToast(VideoUiStrings.uploadSourceNotFound);
        return false;
      }

      final sourceFileSizeBytes = await sourceFile.length();
      if (sourceFileSizeBytes <= 0) {
        showErrorToast(VideoUiStrings.uploadEmptyFile);
        return false;
      }

      if (sourceFileSizeBytes > VideoTools.maxUploadFileSizeBytes) {
        showErrorToast(VideoUiStrings.uploadFileTooLarge);
        return false;
      }

      uploadStage.value = VideoUiStrings.uploadStageAnalyze;
      uploadProgress.value = 0.02;
      originalVideoPath = sourceFile.path;

      final preparedVideo = await VideoTools.prepareVideoFileForUpload(
        sourceFile.path,
        maxDurationSeconds: VideoTools.defaultMaxUploadDurationSeconds,
      );
      if (!_isCurrentOperation(operation)) return false;

      final preparedFileSizeBytes = await preparedVideo.file.length();
      if (preparedFileSizeBytes <= 0) {
        showErrorToast(VideoUiStrings.uploadEmptyFile);
        return false;
      }

      if (preparedFileSizeBytes > VideoTools.maxUploadFileSizeBytes) {
        showErrorToast(VideoUiStrings.uploadFileTooLarge);
        return false;
      }

      final isValidQuality = await VideoTools.isQualityAcceptable(
        preparedVideo.file.path,
      );
      if (!_isCurrentOperation(operation)) return false;

      if (!isValidQuality) {
        showErrorToast(VideoUiStrings.uploadQualityTooLow);
        return false;
      }

      uploadStage.value = VideoUiStrings.uploadStagePrepareFile;
      final (preparedWidth, preparedHeight) = await VideoTools.getDimensions(
        preparedVideo.file.path,
      );
      if (!_isCurrentOperation(operation)) return false;

      uploadProgress.value = 0.08;
      selectedVideo = preparedVideo.file;
      originalVideoPath = selectedVideo!.path;
      _preparedDurationSec = preparedVideo.uploadDurationSeconds;
      _preparedWidth = preparedWidth;
      _preparedHeight = preparedHeight;
      _preparedFileSizeBytes = preparedFileSizeBytes;
      if (preparedVideo.wasTrimmed) {
        showInfoToast(
          VideoUiStrings.uploadTrimmed(
            preparedVideo.uploadDurationSeconds ??
                VideoTools.defaultMaxUploadDurationSeconds,
          ),
        );
      }

      uploadStage.value = VideoUiStrings.uploadStageGenerateThumbnail;
      thumbnail = await _retryThumbnail(selectedVideo!.path);
      if (!_isCurrentOperation(operation)) return false;

      if (thumbnail == null) {
        showErrorToast(VideoUiStrings.uploadThumbnailFailed);
        return false;
      }

      uploadProgress.value = 0.15;
      this.description = sanitizedDescription;
      caption = sanitizedCaption;
      isPrepared = true;
      return true;
    } on VideoPreparationException catch (error, stackTrace) {
      if (!_isCurrentOperation(operation)) return false;
      unawaited(
        _observability.logUploadFailure(
          stage: 'prepare',
          code: 'preparation-error',
          error: error.message,
          stackTrace: stackTrace,
          metadata: _uploadDiagnostics(operation: operation),
        ),
      );
      showErrorToast(error.message);
      return false;
    } catch (error, stackTrace) {
      if (!_isCurrentOperation(operation)) return false;
      unawaited(
        _observability.logUploadFailure(
          stage: 'prepare',
          code: 'unexpected-preparation-error',
          error: error,
          stackTrace: stackTrace,
          metadata: _uploadDiagnostics(operation: operation),
        ),
      );
      showErrorToast(VideoUiStrings.uploadPreparationFailed);
      return false;
    } finally {
      if (_isCurrentOperation(operation)) {
        isPreparing(false);
        if (!isPrepared) {
          uploadProgress.value = 0.0;
          uploadStage.value = '';
        }
      }
    }
  }

  Future<File?> _retryThumbnail(String path, {int attempts = 3}) async {
    for (int i = 0; i < attempts; i++) {
      final thumb = await VideoTools.generateThumbnail(path);
      if (thumb != null) return thumb;
      await Future.delayed(Duration(milliseconds: 600 + (i * 200)));
    }
    return null;
  }

  /// Best-effort lookup of the uploader's profile.
  ///
  /// Returns `null` when the profile can't be hydrated — the upload proceeds
  /// anyway. The profile is not authorization material: `finalizeUpload`
  /// stamps the document with the uid decoded from the caller's ID token, and
  /// `assertUploadCallerEligible` re-checks the role and account state
  /// server-side. The only thing lost without it is the denormalized
  /// `profilePhoto`, a cosmetic field the callable already treats as
  /// optional.
  ///
  /// This used to throw "Impossible de charger le profil" and abort the whole
  /// upload whenever the users/{uid} read was slow or failed — turning a
  /// transient Firestore hiccup into a failed video upload for no security
  /// benefit.
  Future<AppUser?> _resolveCurrentUploadUser(int operation) async {
    final authUid = _authSessionService.currentUid;
    if (authUid == null || authUid.isEmpty) {
      throw const _UploadStageException(
        'auth-required',
        VideoUiStrings.uploadAuthRequired,
      );
    }

    if (!Get.isRegistered<UserController>()) {
      return null;
    }

    final userController = Get.find<UserController>();
    final cachedUser = userController.user;
    if (cachedUser != null && cachedUser.uid == authUid) {
      return cachedUser;
    }

    try {
      await userController.ensureCurrentUserHydrated(force: true);
    } catch (error, stackTrace) {
      unawaited(
        _observability.logUploadInfo(
          event: 'upload_profile_hydration_skipped',
          stage: 'prepare',
          metadata: {
            ..._uploadDiagnostics(operation: operation),
            'error': error.toString(),
          },
        ),
      );
      AppLogger.debug(
        '[UploadVideoController] profile hydration failed, continuing '
        'without it: $error\n$stackTrace',
      );
      return null;
    }

    if (!_isCurrentOperation(operation)) {
      return null;
    }

    final hydratedUser = userController.user;
    if (hydratedUser != null && hydratedUser.uid == authUid) {
      return hydratedUser;
    }

    unawaited(
      _observability.logUploadInfo(
        event: 'upload_profile_hydration_skipped',
        stage: 'prepare',
        metadata: {
          ..._uploadDiagnostics(operation: operation),
          'sessionLoadMessage': userController.sessionLoadMessage,
        },
      ),
    );
    return null;
  }

  /* -------------------------------------------------------------------------- */
  /* Upload principal                                                          */
  /* -------------------------------------------------------------------------- */

  Future<void> uploadDirectly() async {
    if (isPreparing.value) {
      showInfoToast(VideoUiStrings.uploadPreparationInProgress);
      return;
    }

    if (isUploading.value || isOptimizing.value) {
      showInfoToast(VideoUiStrings.uploadAlreadyInProgress);
      return;
    }

    if (selectedVideo == null || thumbnail == null) {
      showErrorToast(VideoUiStrings.uploadMissingFile);
      return;
    }

    isPreparing(false);
    isUploading(true);
    isOptimizing(false);
    final operation = _operationSerial;

    final desc = (description ?? '').trim();
    final cap = (caption ?? '').trim();
    if (desc.isEmpty || cap.isEmpty) {
      showErrorToast(VideoUiStrings.uploadMissingMetadata);
      isUploading(false);
      return;
    }

    // Stays at 0/"still connecting" (rather than jumping to a fixed
    // percentage) while the upload session is still being negotiated, so a
    // slow/retrying App Check handshake reads as "in progress" instead of a
    // stalled progress bar frozen at a number that never moves.
    uploadStage.value = VideoUiStrings.uploadStageLoadProfile;

    UploadSessionState session;
    AppUser? uploadUser;

    try {
      uploadUser = await _resolveCurrentUploadUser(operation);
      if (!_isCurrentOperation(operation)) return;

      uploadStage.value = VideoUiStrings.uploadStageInitialize;
      final fileSizeBytes =
          _preparedFileSizeBytes ?? await selectedVideo!.length();
      if (fileSizeBytes <= 0) {
        showErrorToast(VideoUiStrings.uploadEmptyFile);
        isUploading(false);
        return;
      }

      if (fileSizeBytes > VideoTools.maxUploadFileSizeBytes) {
        showErrorToast(VideoUiStrings.uploadFileTooLarge);
        isUploading(false);
        return;
      }

      try {
        session = await _uploadClient
            .ensureSession(
              localFilePath: selectedVideo!.path,
              fileSizeBytes: fileSizeBytes,
              contentType: 'video/mp4',
            )
            .timeout(_sessionCreationTimeout);
      } on TimeoutException {
        if (!_isCurrentOperation(operation)) return;
        throw const _UploadStageException(
          'session-creation-timeout',
          VideoUiStrings.uploadSessionTimeout,
        );
      }
      if (!_isCurrentOperation(operation)) return;
      _activeSession = session;
      uploadProgress.value = 0.18;

      uploadStage.value = VideoUiStrings.uploadStageUploading;
      _cancelToken = CancelToken();

      final videoUploaded = await _uploadClient.uploadFile(
        session: session,
        file: selectedVideo!,
        cancelToken: _cancelToken,
        onUrlRefreshed: () {
          uploadStage.value = VideoUiStrings.uploadStageRefreshSecureLink;
        },
        onProgress: (p) {
          uploadProgress.value = 0.2 + (0.5 * p);
        },
      );
      if (!_isCurrentOperation(operation)) return;

      if (!videoUploaded) {
        throw const _UploadStageException(
          'video-transfer-failed',
          VideoUiStrings.uploadVideoTransferFailed,
        );
      }

      if (!await thumbnail!.exists() || (await thumbnail!.length()) == 0) {
        final regenerated = await VideoTools.generateThumbnail(
          originalVideoPath!,
        );
        if (regenerated != null && await regenerated.exists()) {
          thumbnail = regenerated;
        } else {
          throw const _UploadStageException(
            'thumbnail-missing',
            VideoUiStrings.uploadMissingThumbnail,
          );
        }
      }
      if (!_isCurrentOperation(operation)) return;

      uploadStage.value = VideoUiStrings.uploadStagePrepareSecureThumbnail;
      final thumbContentType = VideoTools.inferImageContentTypeFromPath(
        thumbnail!.path,
      );

      final thumbTicket = await _uploadClient.requestThumbnailTicket(
        sessionId: session.sessionId,
        file: thumbnail!,
        contentType: thumbContentType,
        thumbnailPath: session.thumbnailPath,
      );
      if (!_isCurrentOperation(operation)) return;
      _lastUploadedThumbPath = thumbTicket.thumbnailPath;

      uploadStage.value = VideoUiStrings.uploadStageSendThumbnail;
      final thumbUploaded = await _uploadClient.uploadThumbnailFile(
        ticket: thumbTicket,
        file: thumbnail!,
        cancelToken: _cancelToken,
        onProgress: (p) {
          uploadProgress.value = 0.7 + (0.25 * p);
        },
      );
      if (!_isCurrentOperation(operation)) return;

      if (!thumbUploaded) {
        throw const _UploadStageException(
          'thumbnail-transfer-failed',
          VideoUiStrings.uploadThumbnailTransferFailed,
        );
      }

      uploadStage.value = VideoUiStrings.uploadStageFinalize;
      uploadProgress.value = 0.95;

      final durationSec = _preparedDurationSec;
      final w = _preparedWidth;
      final h = _preparedHeight;
      final authUid = _authSessionService.currentUid ?? '';

      final finalized = await _uploadClient.finalizeUpload(
        sessionId: session.sessionId,
        metadata: {
          'id': session.sessionId,
          'uid': uploadUser?.uid ?? authUid,
          'profilePhoto': uploadUser?.photoProfil ?? '',
          // songName is the legacy alias for description (not caption) —
          // Video.fromMap reads it back as description, see lib/models/video.dart.
          'description': desc,
          'songName': desc,
          'legend': cap,
          'legende': cap,
          'captionText': cap,
          'caption': cap,
          'storagePath': session.videoPath,
          'thumbnailPath': thumbTicket.thumbnailPath,
          'thumbnailHash': thumbTicket.expectedHash,
          'thumbnailSize': thumbTicket.expectedSize,
          'thumbnailContentType': thumbTicket.contentType,
          'status': 'processing',
          'likes': [],
          'reports': [],
          'reportCount': 0,
          'shareCount': 0,
          'optimized': false,
          'duration': ?durationSec,
          'width': ?w,
          'height': ?h,
        },
      );
      if (!_isCurrentOperation(operation)) return;

      if (!finalized) {
        throw const _UploadStageException(
          'finalize-failed',
          VideoUiStrings.uploadFinalizeFailed,
        );
      }

      await _uploadClient.clearPersistedSession();
      _activeSession = null;
      await _releaseVideoProcessingResources();

      uploadStage.value = VideoUiStrings.uploadStageOptimize;
      isUploading(false);
      isOptimizing(true);

      await _waitForVideoStatusReady(session.sessionId);
      if (!_isCurrentOperation(operation)) return;
      await _cleanupLocalFiles();
    } catch (e, stackTrace) {
      if (!_isCurrentOperation(operation)) return;
      if (e is DioException && CancelToken.isCancel(e)) {
        unawaited(
          _observability.logUploadInfo(
            event: 'upload_cancelled',
            stage: uploadStage.value.isNotEmpty ? uploadStage.value : 'upload',
            sessionId: _activeSession?.sessionId,
            metadata: _uploadDiagnostics(operation: operation),
          ),
        );
        showInfoToast(VideoUiStrings.uploadCancelled);
      } else {
        unawaited(
          _observability.logUploadFailure(
            stage: uploadStage.value.isNotEmpty ? uploadStage.value : 'upload',
            sessionId: _activeSession?.sessionId,
            code: _uploadFailureCode(e),
            error: e,
            stackTrace: stackTrace,
            metadata: _uploadDiagnostics(operation: operation),
          ),
        );
        showErrorToast(_toUserMessage(e));
      }
      isUploading(false);
      // A failure here means the upload did NOT complete, even if it
      // happened after isOptimizing(true) was set while waiting on
      // _waitForVideoStatusReady. Without this, the finally block below
      // skips resetUploadState() (its guard is `!isOptimizing.value`) and
      // the user is stuck on the optimizing overlay with no way out.
      isOptimizing(false);
    } finally {
      if (_isCurrentOperation(operation)) {
        _cancelToken = null;
      }
      if (_isCurrentOperation(operation) && !isOptimizing.value) {
        resetUploadState();
      }
    }
  }

  /* -------------------------------------------------------------------------- */
  /* Attente optimisation                                                      */
  /* -------------------------------------------------------------------------- */

  /// Tears down an optimization watch left running by a discarded controller.
  ///
  /// The watch lives up to [_optimizationOverallTimeout] and holds a Firestore
  /// listener plus two timers. This controller is registered with
  /// `permanent: false` (FeatureControllerRegistry), so leaving the upload
  /// flow disposes it mid-wait — and the timers went on to fire a toast and a
  /// `Get.offAllNamed` from a controller nobody was looking at any more,
  /// yanking the user off whatever screen they had moved to.
  void Function()? _cancelOptimizationWatch;

  Future<void> _waitForVideoStatusReady(String videoId) async {
    final completer = Completer<void>();
    StreamSubscription<UploadVideoProcessingState>? subscription;
    Timer? fallbackTimer;
    Timer? timeoutTimer;
    const failureStatuses = {'error', 'failed', 'failure'};

    Future<void> navigateBackToFeed() async {
      await Future.delayed(const Duration(milliseconds: 200));
      Get.offAllNamed(AppRoutes.main, arguments: {'tab': 0, 'refresh': true});
    }

    Future<void> finalizeSuccessFlow() async {
      isOptimizing(false);
      await Future.delayed(const Duration(milliseconds: 300));
      showSuccessToast(VideoUiStrings.uploadSuccess);
      await navigateBackToFeed();
    }

    Future<void> finalizeReviewFlow() async {
      unawaited(
        _observability.logUploadInfo(
          event: 'upload_submitted_for_review',
          stage: 'optimization',
          sessionId: videoId,
          metadata: _uploadDiagnostics(operation: _operationSerial),
        ),
      );
      isOptimizing(false);
      await Future.delayed(const Duration(milliseconds: 300));
      showInfoToast(VideoUiStrings.uploadSubmittedForReview);
      await navigateBackToFeed();
    }

    Future<void> finalizeFailureFlow(String status) async {
      unawaited(
        _observability.logUploadFailure(
          stage: 'optimization',
          sessionId: videoId,
          code: 'optimization-$status',
          error: 'Video optimization ended with status $status.',
          metadata: _uploadDiagnostics(operation: _operationSerial),
        ),
      );
      isOptimizing(false);
      showErrorToast(VideoUiStrings.uploadOptimizationFailed(status));
      await navigateBackToFeed();
    }

    Future<void> finalizePendingFlow() async {
      unawaited(
        _observability.logUploadInfo(
          event: 'upload_optimization_pending',
          stage: 'optimization',
          sessionId: videoId,
          metadata: _uploadDiagnostics(operation: _operationSerial),
        ),
      );
      isOptimizing(false);
      showInfoToast(VideoUiStrings.uploadOptimizationPending);
      await navigateBackToFeed();
    }

    Future<void> closeOptimizationFlow(Future<void> Function() callback) async {
      if (completer.isCompleted) return;

      _cancelOptimizationWatch = null;
      await subscription?.cancel();
      fallbackTimer?.cancel();
      timeoutTimer?.cancel();
      await callback();
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    // Abandon the watch without running any of the completion flows: the
    // controller is going away, so a toast or a route change would land on
    // whatever screen the user moved to instead. The upload itself is
    // unaffected — it is finished server-side by this point, and the profile
    // shows its state.
    _cancelOptimizationWatch = () {
      unawaited(subscription?.cancel());
      fallbackTimer?.cancel();
      timeoutTimer?.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    };

    Future<void> inspectVideoState(UploadVideoProcessingState state) async {
      final status = state.status;
      final optimized = state.optimized;

      if (status is String && failureStatuses.contains(status)) {
        await closeOptimizationFlow(() => finalizeFailureFlow(status));
        return;
      }

      if (status == 'ready' && optimized) {
        await closeOptimizationFlow(finalizeSuccessFlow);
        return;
      }

      if (optimized && status == 'under_review') {
        await closeOptimizationFlow(finalizeReviewFlow);
        return;
      }
    }

    fallbackTimer = Timer.periodic(_pollInterval, (_) async {
      try {
        final state = await _uploadRepository.fetchProcessingState(videoId);
        await inspectVideoState(state);
      } catch (error) {
        AppLogger.debug(
          '[UploadVideoController] fallback optimization poll error: $error',
        );
      }
    });

    subscription = _uploadRepository
        .watchProcessingState(videoId)
        .listen(
          (state) {
            unawaited(inspectVideoState(state));
          },
          onError: (error) {
            AppLogger.debug(
              '[UploadVideoController] optimization snapshot error: $error',
            );
          },
        );

    timeoutTimer = Timer(_optimizationOverallTimeout, () {
      unawaited(closeOptimizationFlow(finalizePendingFlow));
    });

    return completer.future;
  }

  /* -------------------------------------------------------------------------- */
  /* Cancel / reset                                                            */
  /* -------------------------------------------------------------------------- */

  Future<void> cancelUpload() async {
    if (isOptimizing.value) return;

    if (isPreparing.value) {
      resetUploadState();
      showInfoToast(VideoUiStrings.uploadPreparationCancelled);
      return;
    }

    _cancelToken?.cancel('user-cancelled');
    await _uploadClient.clearPersistedSession();

    if (_activeSession != null) {
      await _deletePartialUpload(
        _activeSession!.videoPath,
        _lastUploadedThumbPath ?? _activeSession!.thumbnailPath,
      );
    }

    resetUploadState();
    showInfoToast(VideoUiStrings.uploadCancelled);
  }

  void resetUploadState() {
    _operationSerial++;
    isPreparing(false);
    isUploading(false);
    isOptimizing(false);
    uploadProgress.value = 0.0;
    uploadStage.value = '';
    selectedVideo = null;
    thumbnail = null;
    description = null;
    caption = null;
    originalVideoPath = null;
    _preparedDurationSec = null;
    _preparedWidth = null;
    _preparedHeight = null;
    _preparedFileSizeBytes = null;
    _cancelToken = null;
    _activeSession = null;
    _lastUploadedThumbPath = null;
  }

  Map<String, dynamic> _uploadDiagnostics({required int operation}) {
    return {
      'operation': operation,
      'stage': uploadStage.value,
      'progress': uploadProgress.value,
      'isPreparing': isPreparing.value,
      'isUploading': isUploading.value,
      'isOptimizing': isOptimizing.value,
      'sessionId': _activeSession?.sessionId,
      'videoPath': _activeSession?.videoPath,
      'thumbnailPath': _lastUploadedThumbPath ?? _activeSession?.thumbnailPath,
      'preparedDurationSec': _preparedDurationSec,
      'preparedWidth': _preparedWidth,
      'preparedHeight': _preparedHeight,
      'preparedFileSizeBytes': _preparedFileSizeBytes,
      'hasSelectedVideo': selectedVideo != null,
      'hasThumbnail': thumbnail != null,
    };
  }

  String _uploadFailureCode(Object error) {
    if (error is _UploadStageException) return error.code;
    return UploadVideoErrorMapper.failureCode(error);
  }

  String _toUserMessage(Object error) {
    if (error is _UploadStageException) return error.message;
    return UploadVideoErrorMapper.toUserMessage(error);
  }

  Future<void> _cleanupLocalFiles() async {
    for (final f in [selectedVideo, thumbnail]) {
      try {
        if (f != null && await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _releaseVideoProcessingResources() async {
    try {
      await VideoTools.dispose();
    } catch (_) {}
  }

  Future<void> _deletePartialUpload(String videoPath, String thumbPath) async {
    try {
      await _uploadRepository.deletePartialUpload(videoPath, thumbPath);
    } catch (_) {}
  }

  Future<void> _cleanupOrphanedSession() async {
    final session = _activeSession;
    if (session == null) return;

    _activeSession = null;
    await _deletePartialUpload(
      session.videoPath,
      _lastUploadedThumbPath ?? session.thumbnailPath,
    );
    _lastUploadedThumbPath = null;
  }
}
