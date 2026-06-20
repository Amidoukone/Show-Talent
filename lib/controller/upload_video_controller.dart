import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/services/video_observability_service.dart';
import 'package:adfoot/services/videos/data/upload_client.dart';
import 'package:adfoot/services/videos/upload_video_error_mapper.dart';
import 'package:adfoot/services/videos/upload_video_repository.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/utils/video_tools.dart';
import 'package:adfoot/screens/success_toast.dart';
import 'package:adfoot/services/app_logger.dart';

class UploadVideoController extends GetxController {
  static const Duration _optimizationOverallTimeout = Duration(seconds: 45);
  static const Duration _pollInterval = Duration(seconds: 10);

  final isUploading = false.obs;
  final isOptimizing = false.obs;
  final isPreparing = false.obs;
  final uploadProgress = 0.0.obs;
  final uploadStage = ''.obs;

  UploadVideoController({
    UploadClient? uploadClient,
    VideoObservabilityService? observability,
    UploadVideoRepository? uploadRepository,
  }) : _uploadClient = uploadClient ?? UploadClient(),
       _observability = observability ?? VideoObservabilityService.instance,
       _uploadRepository = uploadRepository ?? UploadVideoRepository();

  File? selectedVideo;
  File? thumbnail;
  String? description;
  String? caption;
  String? originalVideoPath;

  final UploadClient _uploadClient;
  final VideoObservabilityService _observability;
  final UploadVideoRepository _uploadRepository;
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

  /* -------------------------------------------------------------------------- */
  /* Upload principal                                                          */
  /* -------------------------------------------------------------------------- */

  Future<void> uploadDirectly() async {
    if (isPreparing.value) {
      showInfoToast(VideoUiStrings.uploadPreparationInProgress);
      return;
    }

    if (selectedVideo == null || thumbnail == null) {
      showErrorToast(VideoUiStrings.uploadMissingFile);
      return;
    }

    isPreparing(false);
    isUploading(true);
    isOptimizing(false);

    final desc = (description ?? '').trim();
    final cap = (caption ?? '').trim();
    if (desc.isEmpty || cap.isEmpty) {
      showErrorToast(VideoUiStrings.uploadMissingMetadata);
      isUploading(false);
      return;
    }

    uploadStage.value = VideoUiStrings.uploadStageInitialize;
    uploadProgress.value = 0.18;

    UploadSessionState session;

    try {
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

      session = await _uploadClient.ensureSession(
        localFilePath: selectedVideo!.path,
        fileSizeBytes: fileSizeBytes,
        contentType: 'video/mp4',
      );
      _activeSession = session;

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

      if (!videoUploaded) {
        throw VideoUiStrings.uploadVideoTransferFailed;
      }

      if (!await thumbnail!.exists() || (await thumbnail!.length()) == 0) {
        final regenerated = await VideoTools.generateThumbnail(
          originalVideoPath!,
        );
        if (regenerated != null && await regenerated.exists()) {
          thumbnail = regenerated;
        } else {
          throw VideoUiStrings.uploadMissingThumbnail;
        }
      }

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

      if (!thumbUploaded) {
        throw VideoUiStrings.uploadThumbnailTransferFailed;
      }

      uploadStage.value = VideoUiStrings.uploadStageFinalize;
      uploadProgress.value = 0.95;

      final durationSec = _preparedDurationSec;
      final w = _preparedWidth;
      final h = _preparedHeight;
      final user = Get.find<UserController>().user;

      final finalized = await _uploadClient.finalizeUpload(
        sessionId: session.sessionId,
        metadata: {
          'id': session.sessionId,
          'uid': user?.uid ?? '',
          'profilePhoto': user?.photoProfil ?? '',
          // Keep duplicated copy in legacy `songName` for compatibility.
          'description': desc,
          'legend': cap,
          'legende': cap,
          'captionText': cap,
          'caption': cap,
          'songName': cap,
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

      if (!finalized) {
        throw VideoUiStrings.uploadFinalizeFailed;
      }

      await _uploadClient.clearPersistedSession();
      _activeSession = null;
      await _releaseVideoProcessingResources();

      uploadStage.value = VideoUiStrings.uploadStageOptimize;
      isUploading(false);
      isOptimizing(true);

      await _waitForVideoStatusReady(session.sessionId);
      await _cleanupLocalFiles();
    } catch (e, stackTrace) {
      if (e is DioException && CancelToken.isCancel(e)) {
        unawaited(
          _observability.logUploadInfo(
            event: 'upload_cancelled',
            stage: uploadStage.value.isNotEmpty ? uploadStage.value : 'upload',
            sessionId: _activeSession?.sessionId,
            metadata: _uploadDiagnostics(operation: _operationSerial),
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
            metadata: _uploadDiagnostics(operation: _operationSerial),
          ),
        );
        showErrorToast(_toUserMessage(e));
      }
      isUploading(false);
    } finally {
      _cancelToken = null;
      if (!isOptimizing.value) {
        resetUploadState();
      }
    }
  }

  /* -------------------------------------------------------------------------- */
  /* Attente optimisation                                                      */
  /* -------------------------------------------------------------------------- */

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

      await subscription?.cancel();
      fallbackTimer?.cancel();
      timeoutTimer?.cancel();
      await callback();
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

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
    return UploadVideoErrorMapper.failureCode(error);
  }

  String _toUserMessage(Object error) {
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
}
