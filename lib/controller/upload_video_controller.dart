import 'dart:async';
import 'dart:io';

import 'package:adfoot/widgets/processing_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/utils/video_tools.dart';
import 'package:adfoot/screens/success_toast.dart';

class UploadVideoController extends GetxController {
  var isUploading = false.obs;
  var isOptimizing = false.obs;
  var uploadProgress = 0.0.obs;
  var uploadStage = ''.obs;

  File? selectedVideo;
  File? thumbnail;
  String? songName;
  String? caption;
  String? originalVideoPath;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _internetAvailable = true;
  bool _wasPaused = false;
  UploadTask? _currentUploadTask;

  @override
  void onInit() {
    super.onInit();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((resultList) {
      final result = resultList.firstOrNull;
      _internetAvailable =
          result != null && result != ConnectivityResult.none;
    });
  }

  @override
  void onClose() {
    _connectivitySubscription?.cancel();
    VideoTools.dispose();
    super.onClose();
  }

  Future<bool> _checkRealInternetAccess() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> prepareUpload({
    required String song,
    required String cap,
    required String videoPath,
  }) async {
    try {
      uploadStage.value = "Analyse de la vidéo...";
      uploadProgress.value = 0.02;
      originalVideoPath = videoPath;

      final isValidDuration =
          await VideoTools.isDurationValid(videoPath, maxDuration: 62);
      final isValidQuality =
          await VideoTools.isQualityAcceptable(videoPath);

      if (!isValidDuration || !isValidQuality) {
        if (Get.isDialogOpen == true) Get.back();
        showErrorToast(!isValidDuration
            ? 'La durée dépasse 60 secondes.'
            : 'Qualité vidéo insuffisante (minimum 480×360).');
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
      songName = song.trim();
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

  Future<void> uploadDirectly() async {
    if (selectedVideo == null || thumbnail == null) {
      showErrorToast('Fichier manquant');
      return;
    }

    _internetAvailable = await _checkRealInternetAccess();
    isUploading(true);
    isOptimizing(false);
    uploadStage.value = "Téléversement...";
    uploadProgress.value = 0.2;

    final videoId = const Uuid().v4();

    final thumbContentType =
        VideoTools.inferImageContentTypeFromPath(thumbnail!.path);
    final thumbExt = thumbContentType == 'image/png' ? 'png' : 'jpg';

    final videoPath = 'videos/$videoId.mp4';
    final thumbPath = 'thumbnails/thumbnail_$videoId.$thumbExt';

    final videoRef = FirebaseStorage.instance.ref().child(videoPath);
    final thumbRef = FirebaseStorage.instance.ref().child(thumbPath);

    final user = Get.find<UserController>().user;
    final now = Timestamp.now();

    final durationSec =
        await VideoTools.getDurationSeconds(originalVideoPath!);
    final (w, h) = await VideoTools.getDimensions(originalVideoPath!);

    await FirebaseFirestore.instance
        .collection('videos')
        .doc(videoId)
        .set({
      'id': videoId,
      'videoUrl': '',
      'thumbnail': '',
      'songName': songName,
      'caption': caption,
      'likes': [],
      'shareCount': 0,
      'reports': [],
      'reportCount': 0,
      'uid': user?.uid ?? '',
      'profilePhoto': user?.photoProfil ?? '',
      'createdAt': now,
      'updatedAt': now,
      'status': 'processing',
      'optimized': false,
      if (durationSec != null) 'duration': durationSec,
      if (w != null) 'width': w,
      if (h != null) 'height': h,
    });

    bool cleanupOnFailure = false;

    try {
      final videoUploaded = await _retryUploadFile(
        file: selectedVideo!,
        storageRef: videoRef,
        onProgress: (p) =>
            uploadProgress.value = 0.2 + (0.45 * p),
        contentType: 'video/mp4',
      );

      if (!videoUploaded) {
        cleanupOnFailure = true;
        throw 'Échec upload vidéo';
      }

      if (!await thumbnail!.exists() || (await thumbnail!.length()) == 0) {
        final regenerated =
            await VideoTools.generateThumbnail(originalVideoPath!);
        if (regenerated != null && await regenerated.exists()) {
          thumbnail = regenerated;
        } else {
          cleanupOnFailure = true;
          throw 'Miniature manquante';
        }
      }

      final thumbUploaded = await _retryUploadFile(
        file: thumbnail!,
        storageRef: thumbRef,
        onProgress: (p) =>
            uploadProgress.value = 0.65 + (0.35 * p),
        contentType: thumbContentType,
      );

      if (!thumbUploaded) {
        cleanupOnFailure = true;
        throw 'Échec upload miniature';
      }

      await FirebaseFirestore.instance
          .collection('videos')
          .doc(videoId)
          .update({
        'storagePath': videoPath,
        'thumbnailPath': thumbPath,
        'updatedAt': Timestamp.now(),
      });

      uploadStage.value = "Optimisation en cours...";
      isUploading(false);
      isOptimizing(true);

      await _waitForVideoStatusReady(videoId);
    } catch (e) {
      if (cleanupOnFailure) {
        await _deletePartialUpload(videoPath, thumbPath);
      }
      showErrorToast(e.toString());
    } finally {
      await _cleanupLocalFiles();
      resetUploadState();
    }
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

  Future<void> _deletePartialUpload(
      String videoPath, String thumbPath) async {
    try {
      final videoRef = FirebaseStorage.instance.ref(videoPath);
      final thumbRef = FirebaseStorage.instance.ref(thumbPath);
      await Future.wait([
        videoRef.delete().catchError((_) {}),
        thumbRef.delete().catchError((_) {}),
      ]);
    } catch (_) {}
  }

  Future<bool> _safeUploadFile({
    required File file,
    required Reference storageRef,
    required Function(double) onProgress,
    String? contentType,
  }) async {
    try {
      final meta = SettableMetadata(
        contentType: contentType ??
            (file.path.toLowerCase().endsWith('.mp4')
                ? 'video/mp4'
                : VideoTools.inferImageContentTypeFromPath(file.path)),
        cacheControl: 'public,max-age=86400',
      );

      final uploadTask = storageRef.putFile(file, meta);
      _currentUploadTask = uploadTask;

      final completer = Completer<bool>();

      uploadTask.snapshotEvents.listen((snapshot) async {
        switch (snapshot.state) {
          case TaskState.running:
            final total = snapshot.totalBytes;
            final sent = snapshot.bytesTransferred;
            final progress = total > 0 ? sent / total : 0.0;
            onProgress(progress);
            _handleNetworkLossDuringUpload();
            break;
          case TaskState.success:
            completer.complete(true);
            break;
          case TaskState.error:
          case TaskState.canceled:
            completer.complete(false);
            break;
          default:
            break;
        }
      }, onError: (_) => completer.complete(false));

      return await completer.future
          .timeout(const Duration(minutes: 5), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _retryUploadFile({
    required File file,
    required Reference storageRef,
    required Function(double) onProgress,
    String? contentType,
    int maxRetries = 3,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      final success = await _safeUploadFile(
        file: file,
        storageRef: storageRef,
        onProgress: onProgress,
        contentType: contentType,
      );
      if (success) return true;
      await Future.delayed(Duration(seconds: 1 << attempt)); // backoff 1s,2s,4s
    }
    return false;
  }

  void _handleNetworkLossDuringUpload() async {
    if (!_internetAvailable &&
        _currentUploadTask != null &&
        _currentUploadTask!.snapshot.state == TaskState.running) {
      await _currentUploadTask!.pause();
      _wasPaused = true;
      showInfoToast('Connexion perdue, upload en pause.');
    } else if (_wasPaused &&
        _internetAvailable &&
        _currentUploadTask?.snapshot.state == TaskState.paused) {
      await _currentUploadTask!.resume();
      _wasPaused = false;
      showInfoToast('Connexion rétablie, upload repris.');
    }
  }

  Future<void> _waitForVideoStatusReady(String videoId) async {
    final completer = Completer<void>();
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
        subscription;
    Timer? fallbackTimer;

    if (!(Get.isDialogOpen ?? false)) {
      Get.dialog(
        const ProcessingDialog(),
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.7),
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

    fallbackTimer =
        Timer.periodic(const Duration(seconds: 10), (_) async {
      final doc = await FirebaseFirestore.instance
          .collection('videos')
          .doc(videoId)
          .get();
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

    Future.delayed(const Duration(minutes: 3), () async {
      if (!completer.isCompleted) {
        await subscription?.cancel();
        fallbackTimer?.cancel();
        if (Get.isDialogOpen ?? false) Get.back();
        isOptimizing(false);

        showInfoToast(
            'Votre vidéo est en cours d’optimisation. Elle sera visible sous peu.');
        await Future.delayed(const Duration(milliseconds: 200));
        Get.offAllNamed('/main', arguments: {'tab': 0, 'refresh': true});

        completer.complete();
      }
    });

    return completer.future;
  }

  void cancelUpload() {
    if (isOptimizing.value) return;
    _currentUploadTask?.cancel();
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
    songName = null;
    caption = null;
    originalVideoPath = null;
    _currentUploadTask = null;
    _wasPaused = false;
  }
}
