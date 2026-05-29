import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/services/video_observability_service.dart';
import 'package:adfoot/services/videos/data/upload_client.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/utils/video_tools.dart';
import 'package:adfoot/screens/success_toast.dart';

class UploadVideoController extends GetxController {
  static const Duration _optimizationOverallTimeout = Duration(seconds: 45);
  static const Duration _pollInterval = Duration(seconds: 10);

  final isUploading = false.obs;
  final isOptimizing = false.obs;
  final isPreparing = false.obs;
  final uploadProgress = 0.0.obs;
  final uploadStage = ''.obs;

  File? selectedVideo;
  File? thumbnail;
  String? description;
  String? caption;
  String? originalVideoPath;

  final UploadClient _uploadClient = UploadClient();
  final VideoObservabilityService _observability =
      VideoObservabilityService.instance;
  CancelToken? _cancelToken;

  UploadSessionState? _activeSession;
  String? _lastUploadedThumbPath;
  int _operationSerial = 0;
  int? _preparedDurationSec;
  int? _preparedWidth;
  int? _preparedHeight;

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

    var isPrepared = false;

    try {
      final sourceFile = File(videoPath);
      if (!await sourceFile.exists()) {
        showErrorToast(VideoUiStrings.uploadSourceNotFound);
        return false;
      }

      if (await sourceFile.length() <= 0) {
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

      final isValidQuality =
          await VideoTools.isQualityAcceptable(preparedVideo.file.path);
      if (!_isCurrentOperation(operation)) return false;

      if (!isValidQuality) {
        showErrorToast(VideoUiStrings.uploadQualityTooLow);
        return false;
      }

      uploadStage.value = VideoUiStrings.uploadStagePrepareFile;
      final (preparedWidth, preparedHeight) =
          await VideoTools.getDimensions(preparedVideo.file.path);
      if (!_isCurrentOperation(operation)) return false;

      uploadProgress.value = 0.08;
      selectedVideo = preparedVideo.file;
      originalVideoPath = selectedVideo!.path;
      _preparedDurationSec = preparedVideo.uploadDurationSeconds;
      _preparedWidth = preparedWidth;
      _preparedHeight = preparedHeight;
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
      showErrorToast(
        VideoUiStrings.uploadPreparationFailed,
      );
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
      session = await _uploadClient.ensureSession(
        localFilePath: selectedVideo!.path,
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
        final regenerated =
            await VideoTools.generateThumbnail(originalVideoPath!);
        if (regenerated != null && await regenerated.exists()) {
          thumbnail = regenerated;
        } else {
          throw VideoUiStrings.uploadMissingThumbnail;
        }
      }

      uploadStage.value = VideoUiStrings.uploadStagePrepareSecureThumbnail;
      final thumbContentType =
          VideoTools.inferImageContentTypeFromPath(thumbnail!.path);

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
          if (durationSec != null) 'duration': durationSec,
          if (w != null) 'width': w,
          if (h != null) 'height': h,
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
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subscription;
    Timer? fallbackTimer;
    Timer? timeoutTimer;
    const failureStatuses = {'error', 'failed', 'failure'};

    Future<void> navigateBackToFeed() async {
      await Future.delayed(const Duration(milliseconds: 200));
      Get.offAllNamed(
        AppRoutes.main,
        arguments: {
          'tab': 0,
          'refresh': true,
          'videoId': videoId,
          'autoplay': true,
        },
      );
    }

    Future<void> finalizeSuccessFlow() async {
      isOptimizing(false);
      await Future.delayed(const Duration(milliseconds: 300));
      showSuccessToast(VideoUiStrings.uploadSuccess);
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

    Future<void> closeOptimizationFlow(
      Future<void> Function() callback,
    ) async {
      if (completer.isCompleted) return;

      await subscription?.cancel();
      fallbackTimer?.cancel();
      timeoutTimer?.cancel();
      await callback();
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    Future<void> inspectVideoState(Map<String, dynamic>? data) async {
      final status = data?['status'];
      final optimized = data?['optimized'] == true;

      if (status is String && failureStatuses.contains(status)) {
        await closeOptimizationFlow(() => finalizeFailureFlow(status));
        return;
      }

      if (status == 'ready' && optimized) {
        await closeOptimizationFlow(finalizeSuccessFlow);
      }
    }

    fallbackTimer = Timer.periodic(_pollInterval, (_) async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('videos')
            .doc(videoId)
            .get();
        await inspectVideoState(doc.data());
      } catch (error) {
        debugPrint(
          '[UploadVideoController] fallback optimization poll error: $error',
        );
      }
    });

    subscription = FirebaseFirestore.instance
        .collection('videos')
        .doc(videoId)
        .snapshots()
        .listen(
      (doc) {
        unawaited(inspectVideoState(doc.data()));
      },
      onError: (error) {
        debugPrint(
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
      'hasSelectedVideo': selectedVideo != null,
      'hasThumbnail': thumbnail != null,
    };
  }

  String _uploadFailureCode(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.code;
    }
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null) return 'http-$statusCode';
      return error.type.name;
    }
    if (error is UploadClientException) {
      return error.statusCode != null
          ? 'upload-client-${error.statusCode}'
          : 'upload-client';
    }
    return 'upload-error';
  }

  String _toUserMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      if (error.code == 'unauthenticated') {
        return VideoUiStrings.uploadAuthRequired;
      }

      final message = (error.message ?? '').trim();
      if (message.isNotEmpty) {
        return message;
      }

      switch (error.code) {
        case 'permission-denied':
          return VideoUiStrings.uploadPermissionDenied;
        case 'resource-exhausted':
          return VideoUiStrings.uploadServiceUnavailable;
        case 'failed-precondition':
          return VideoUiStrings.uploadPreconditionFailed;
        default:
          return VideoUiStrings.uploadServerError;
      }
    }

    final normalized = error.toString();
    if (normalized.startsWith('Exception: ')) {
      return normalized.substring('Exception: '.length);
    }
    if (normalized.trim().isEmpty) {
      return VideoUiStrings.uploadUnknownError;
    }
    return normalized;
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
      final videoRef = FirebaseStorage.instance.ref(videoPath);
      final thumbRef = FirebaseStorage.instance.ref(thumbPath);
      await Future.wait([
        videoRef.delete().catchError((_) {}),
        thumbRef.delete().catchError((_) {}),
      ]);
    } catch (_) {}
  }
}
