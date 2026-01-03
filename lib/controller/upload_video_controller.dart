import 'dart:async';
import 'dart:io';

import 'package:adfoot/widgets/processing_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/services/videos/data/upload_client.dart';
import 'package:adfoot/utils/video_tools.dart';
import 'package:adfoot/screens/success_toast.dart';

class UploadVideoController extends GetxController {
  static const Duration _optimizationOverallTimeout = Duration(minutes: 3);
  static const Duration _pollInterval = Duration(seconds: 10);

  final isUploading = false.obs;
  final isOptimizing = false.obs;
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
    try {
      uploadStage.value = "Analyse de la vidéo...";
      uploadProgress.value = 0.02;
      originalVideoPath = videoPath;

      final isValidDuration =
          await VideoTools.isDurationValid(videoPath, maxDuration: 62);
      final isValidQuality = await VideoTools.isQualityAcceptable(videoPath);

      if (!isValidDuration || !isValidQuality) {
        if (Get.isDialogOpen == true) Get.back();
        showErrorToast(
          !isValidDuration
              ? 'La durée dépasse 60 secondes.'
              : 'Qualité vidéo insuffisante (minimum 480×360).',
        );
        return false;
      }

      uploadStage.value = "Préparation du fichier...";
      uploadProgress.value = 0.08;
      selectedVideo = File(videoPath);

      uploadStage.value = "Génération de la miniature...";
      thumbnail = await _retryThumbnail(videoPath);
      if (thumbnail == null) {
        if (Get.isDialogOpen == true) Get.back();
        showErrorToast('Erreur lors de la génération de la miniature.');
        return false;
      }

      uploadProgress.value = 0.15;
      this.description = description.trim();
      caption = cap.trim();
      return true;
    } catch (e) {
      if (Get.isDialogOpen == true) Get.back();
      showErrorToast(e.toString());
      return false;
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
    if (selectedVideo == null || thumbnail == null) {
      showErrorToast('Fichier manquant');
      return;
    }

    isUploading(true);
    isOptimizing(false);

    uploadStage.value = "Initialisation...";
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

      uploadStage.value = "Téléversement...";
      _cancelToken = CancelToken();

      final videoUploaded = await _uploadClient.uploadFile(
        session: session,
        file: selectedVideo!,
        cancelToken: _cancelToken,
        onUrlRefreshed: () {
          uploadStage.value = "Renouvellement du lien sécurisé...";
        },
        onProgress: (p) {
          uploadProgress.value = 0.2 + (0.5 * p);
        },
      );

      if (!videoUploaded) {
        throw 'Échec upload vidéo';
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

      uploadStage.value = "Préparation miniature sécurisée...";
      final thumbTicket = await _uploadClient.requestThumbnailTicket(
        sessionId: session.sessionId,
        file: thumbnail!,
        contentType: thumbContentType,
        thumbnailPath: session.thumbnailPath,
      );
      _lastUploadedThumbPath = thumbTicket.thumbnailPath;

      uploadStage.value = "Envoi de la miniature...";
      final thumbUploaded = await _uploadClient.uploadThumbnailFile(
        ticket: thumbTicket,
        file: thumbnail!,
        cancelToken: _cancelToken,
        onProgress: (p) {
          uploadProgress.value = 0.7 + (0.25 * p);
        },
      );

      if (!thumbUploaded) {
        throw 'Échec upload miniature';
      }

      uploadStage.value = "Finalisation...";
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
          // On stocke la description et on duplique pour l’ancien champ `songName`
          'description': description,
          'songName': description,
          'caption': caption,
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
        throw 'Échec finalisation serveur';
      }

      await _uploadClient.clearPersistedSession();
      _activeSession = null;

      uploadStage.value = "Optimisation en cours...";
      isUploading(false);
      isOptimizing(true);

      await _waitForVideoStatusReady(session.sessionId);
      await _cleanupLocalFiles();
    } catch (e) {
      showErrorToast(e.toString());
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

    if (!(Get.isDialogOpen ?? false)) {
      Get.dialog(
        const ProcessingDialog(),
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.7),
      );
    }

    Future<void> finalizeSuccessFlow() async {
      if (completer.isCompleted) return;

      isOptimizing(false);
      if (Get.isDialogOpen ?? false) Get.back();

      await Future.delayed(const Duration(milliseconds: 300));
      showSuccessToast('Vidéo ajoutée avec succès !');

      await Future.delayed(const Duration(milliseconds: 400));
      Get.offAllNamed('/main', arguments: {'tab': 0, 'refresh': true});

      completer.complete();
    }

    fallbackTimer = Timer.periodic(_pollInterval, (_) async {
      final doc =
          await FirebaseFirestore.instance.collection('videos').doc(videoId).get();
      final data = doc.data();
      if (data?['status'] == 'ready' && data?['optimized'] == true) {
        await subscription?.cancel();
        fallbackTimer?.cancel();
        await finalizeSuccessFlow();
      }
    });

    subscription = FirebaseFirestore.instance
        .collection('videos')
        .doc(videoId)
        .snapshots()
        .listen((doc) async {
      final status = doc.data()?['status'];
      final optimized = doc.data()?['optimized'] ?? false;

      if (status == 'ready' && optimized == true) {
        await subscription?.cancel();
        fallbackTimer?.cancel();
        await finalizeSuccessFlow();
      }
    });

    Future.delayed(_optimizationOverallTimeout, () async {
      if (!completer.isCompleted) {
        await subscription?.cancel();
        fallbackTimer?.cancel();
        if (Get.isDialogOpen ?? false) Get.back();
        isOptimizing(false);

        showInfoToast(
          'Votre vidéo est en cours d’optimisation. Elle sera visible sous peu.',
        );
        await Future.delayed(const Duration(milliseconds: 200));
        Get.offAllNamed('/main', arguments: {'tab': 0, 'refresh': true});

        completer.complete();
      }
    });

    return completer.future;
  }

  /* -------------------------------------------------------------------------- */
  /* Cancel / reset                                                            */
  /* -------------------------------------------------------------------------- */

  Future<void> cancelUpload() async {
    if (isOptimizing.value) return;

    _cancelToken?.cancel('user-cancelled');
    await _uploadClient.clearPersistedSession();

    if (_activeSession != null) {
      await _deletePartialUpload(
        _activeSession!.videoPath,
        _lastUploadedThumbPath ?? _activeSession!.thumbnailPath,
      );
    }

    resetUploadState();

    if (Get.isDialogOpen == true) {
      Get.back();
    }
    showInfoToast('Téléversement annulé.');
  }

  void resetUploadState() {
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
