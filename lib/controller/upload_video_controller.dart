import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/services/videos/data/upload_client.dart';
import 'package:adfoot/utils/video_tools.dart';
import 'package:adfoot/screens/success_toast.dart';

class UploadVideoController extends GetxController {
  static const Duration _optimizationOverallTimeout = Duration(minutes: 3);
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
  CancelToken? _cancelToken;

  UploadSessionState? _activeSession;
  String? _lastUploadedThumbPath;

  @override
  void onClose() {
    VideoTools.dispose();
    super.onClose();
  }

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

    if (sanitizedDescription.isEmpty || sanitizedCaption.isEmpty) {
      showErrorToast('Merci de renseigner une description et une legende.');
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

    var isPrepared = false;

    try {
      final sourceFile = File(videoPath);
      if (!await sourceFile.exists()) {
        showErrorToast('Video introuvable. Merci de reessayer.');
        return false;
      }

      if (await sourceFile.length() <= 0) {
        showErrorToast('Le fichier video est vide.');
        return false;
      }

      uploadStage.value = 'Analyse de la video...';
      uploadProgress.value = 0.02;
      originalVideoPath = sourceFile.path;

      final isValidDuration =
          await VideoTools.isDurationValid(sourceFile.path, maxDuration: 62);
      final isValidQuality =
          await VideoTools.isQualityAcceptable(sourceFile.path);

      if (!isValidDuration || !isValidQuality) {
        showErrorToast(
          !isValidDuration
              ? 'La duree depasse 60 secondes.'
              : 'Qualite video insuffisante (minimum 480x360).',
        );
        return false;
      }

      uploadStage.value = 'Preparation du fichier...';
      uploadProgress.value = 0.08;
      selectedVideo = sourceFile;

      uploadStage.value = 'Generation de la miniature...';
      thumbnail = await _retryThumbnail(sourceFile.path);
      if (thumbnail == null) {
        showErrorToast('Erreur lors de la generation de la miniature.');
        return false;
      }

      uploadProgress.value = 0.15;
      this.description = sanitizedDescription;
      caption = sanitizedCaption;
      isPrepared = true;
      return true;
    } catch (_) {
      showErrorToast(
        'Preparation impossible pour le moment. Merci de reessayer.',
      );
      return false;
    } finally {
      isPreparing(false);
      if (!isPrepared) {
        uploadProgress.value = 0.0;
        uploadStage.value = '';
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
      showInfoToast('Preparation en cours...');
      return;
    }

    if (selectedVideo == null || thumbnail == null) {
      showErrorToast('Fichier manquant.');
      return;
    }

    isPreparing(false);
    isUploading(true);
    isOptimizing(false);

    final desc = (description ?? '').trim();
    final cap = (caption ?? '').trim();
    if (desc.isEmpty || cap.isEmpty) {
      showErrorToast('Description ou legende manquante.');
      isUploading(false);
      return;
    }

    uploadStage.value = 'Initialisation...';
    uploadProgress.value = 0.18;

    final thumbContentType =
        VideoTools.inferImageContentTypeFromPath(thumbnail!.path);

    UploadSessionState session;

    try {
      session = await _uploadClient.ensureSession(
        localFilePath: selectedVideo!.path,
        contentType: 'video/mp4',
      );
      _activeSession = session;

      uploadStage.value = 'Televersement...';
      _cancelToken = CancelToken();

      final videoUploaded = await _uploadClient.uploadFile(
        session: session,
        file: selectedVideo!,
        cancelToken: _cancelToken,
        onUrlRefreshed: () {
          uploadStage.value = 'Renouvellement du lien securise...';
        },
        onProgress: (p) {
          uploadProgress.value = 0.2 + (0.5 * p);
        },
      );

      if (!videoUploaded) {
        throw 'Echec upload video';
      }

      if (!await thumbnail!.exists() || (await thumbnail!.length()) == 0) {
        final regenerated =
            await VideoTools.generateThumbnail(originalVideoPath!);
        if (regenerated != null && await regenerated.exists()) {
          thumbnail = regenerated;
        } else {
          throw 'Miniature manquante';
        }
      }

      uploadStage.value = 'Preparation miniature securisee...';
      final thumbTicket = await _uploadClient.requestThumbnailTicket(
        sessionId: session.sessionId,
        file: thumbnail!,
        contentType: thumbContentType,
        thumbnailPath: session.thumbnailPath,
      );
      _lastUploadedThumbPath = thumbTicket.thumbnailPath;

      uploadStage.value = 'Envoi de la miniature...';
      final thumbUploaded = await _uploadClient.uploadThumbnailFile(
        ticket: thumbTicket,
        file: thumbnail!,
        cancelToken: _cancelToken,
        onProgress: (p) {
          uploadProgress.value = 0.7 + (0.25 * p);
        },
      );

      if (!thumbUploaded) {
        throw 'Echec upload miniature';
      }

      uploadStage.value = 'Finalisation...';
      uploadProgress.value = 0.95;

      final durationSec =
          await VideoTools.getDurationSeconds(originalVideoPath!);
      final (w, h) = await VideoTools.getDimensions(originalVideoPath!);
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
        throw 'Echec finalisation serveur';
      }

      await _uploadClient.clearPersistedSession();
      _activeSession = null;

      uploadStage.value = 'Optimisation en cours...';
      isUploading(false);
      isOptimizing(true);

      await _waitForVideoStatusReady(session.sessionId);
      await _cleanupLocalFiles();
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        showInfoToast('Televersement annule.');
      } else {
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
        arguments: {'tab': 0, 'refresh': true},
      );
    }

    Future<void> finalizeSuccessFlow() async {
      isOptimizing(false);
      await Future.delayed(const Duration(milliseconds: 300));
      showSuccessToast('Video ajoutee avec succes !');
      await navigateBackToFeed();
    }

    Future<void> finalizeFailureFlow(String status) async {
      isOptimizing(false);
      showErrorToast(
        "Echec d'optimisation video (statut: $status). Merci de reessayer.",
      );
      await navigateBackToFeed();
    }

    Future<void> finalizePendingFlow() async {
      isOptimizing(false);
      showInfoToast(
        'Votre video est en cours d\'optimisation. Elle sera visible sous peu.',
      );
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
      showInfoToast('Preparation annulee.');
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
    showInfoToast('Televersement annule.');
  }

  void resetUploadState() {
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
    _cancelToken = null;
    _activeSession = null;
    _lastUploadedThumbPath = null;
  }

  String _toUserMessage(Object error) {
    final normalized = error.toString();
    if (normalized.startsWith('Exception: ')) {
      return normalized.substring('Exception: '.length);
    }
    if (normalized.trim().isEmpty) {
      return 'Erreur pendant le televersement.';
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
