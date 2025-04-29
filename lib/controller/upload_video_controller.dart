import 'dart:async';
import 'dart:io';
import 'package:adfoot/screens/success_toast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/utils/video_tools.dart';
import 'package:video_compress/video_compress.dart';

class UploadVideoController extends GetxController {
  var isUploading = false.obs;
  var uploadProgress = 0.0.obs;
  var uploadStage = ''.obs;

  File? selectedVideo;
  File? thumbnail;
  String? songName;
  String? caption;
  String? originalVideoPath;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Subscription? _compressionSubscription;
  bool _internetAvailable = true;
  UploadTask? _currentUploadTask;

  @override
  void onInit() {
    super.onInit();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _internetAvailable = results.contains(ConnectivityResult.mobile) || results.contains(ConnectivityResult.wifi);
    });
  }

  @override
  void onClose() {
    _connectivitySubscription?.cancel();
    _compressionSubscription?.unsubscribe();
    VideoTools.dispose();
    super.onClose();
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

      final isValidDuration = await VideoTools.isDurationValid(videoPath, maxDuration: 60);
      final isValidQuality = await VideoTools.isQualityAcceptable(videoPath);

      if (!isValidDuration) {
        Get.back();
        Get.snackbar('Erreur', 'La durée dépasse 60 secondes.', backgroundColor: Colors.orangeAccent, colorText: Colors.white);
        return false;
      }

      if (!isValidQuality) {
        Get.back();
        Get.snackbar('Erreur', 'Qualité vidéo insuffisante (minimum 360p).', backgroundColor: Colors.orangeAccent, colorText: Colors.white);
        return false;
      }

      uploadStage.value = "Compression vidéo...";
      uploadProgress.value = 0.05;

      _compressionSubscription = VideoCompress.compressProgress$.subscribe((progress) {
        if (progress < 100) {
          uploadProgress.value = 0.05 + (progress * 0.2 / 100);
        }
      });

      final compressed = await VideoTools.compressVideoSilently(videoPath);

      _compressionSubscription?.unsubscribe();

      if (compressed != null) {
        selectedVideo = compressed;
        uploadProgress.value = 0.25;
      } else {
        selectedVideo = File(videoPath);
        uploadStage.value = "Compression échouée, envoi original...";
        uploadProgress.value = 0.15;
      }

      thumbnail = await VideoTools.generateThumbnail(videoPath);
      if (thumbnail == null) {
        Get.back();
        Get.snackbar('Erreur', 'Erreur génération miniature.', backgroundColor: Colors.redAccent, colorText: Colors.white);
        return false;
      }

      uploadProgress.value = 0.3;
      songName = song;
      caption = cap;
      return true;
    } catch (e) {
      _compressionSubscription?.unsubscribe();
      Get.back();
      Get.snackbar('Erreur', '$e', backgroundColor: Colors.redAccent, colorText: Colors.white);
      return false;
    }
  }

  Future<void> uploadDirectly() async {
    if (selectedVideo == null || thumbnail == null) {
      Get.snackbar('Erreur', 'Fichier manquant', backgroundColor: Colors.redAccent, colorText: Colors.white);
      return;
    }

    isUploading(true);
    uploadStage.value = "Téléversement...";
    uploadProgress.value = 0.3;

    final videoId = const Uuid().v4();
    final videoRef = FirebaseStorage.instance.ref().child('videos/$videoId.mp4');
    final thumbRef = FirebaseStorage.instance.ref().child('thumbnails/thumbnail_$videoId.jpg');

    try {
      bool videoUploaded = await _safeUploadFile(
        file: selectedVideo!,
        storageRef: videoRef,
        onProgress: (p) => uploadProgress.value = 0.3 + (0.35 * p),
      );

      if (!videoUploaded) {
        Get.snackbar('Erreur Téléversement', 'Échec upload vidéo.', backgroundColor: Colors.redAccent, colorText: Colors.white);
        resetUploadState();
        return;
      }

      bool thumbUploaded = await _safeUploadFile(
        file: thumbnail!,
        storageRef: thumbRef,
        onProgress: (p) => uploadProgress.value = 0.65 + (0.35 * p),
      );

      if (!thumbUploaded) {
        Get.snackbar('Erreur Téléversement', 'Échec upload miniature.', backgroundColor: Colors.redAccent, colorText: Colors.white);
        resetUploadState();
        return;
      }

      final videoUrl = await videoRef.getDownloadURL();
      final thumbnailUrl = await thumbRef.getDownloadURL();
      final user = Get.find<UserController>().user;

      await FirebaseFirestore.instance.collection('videos').doc(videoId).set({
        'id': videoId,
        'videoUrl': videoUrl,
        'thumbnail': thumbnailUrl,
        'songName': songName,
        'caption': caption,
        'likes': [],
        'shareCount': 0,
        'reports': [],
        'reportCount': 0,
        'uid': user?.uid ?? '',
        'profilePhoto': user?.photoProfil ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'ready',
      });

      uploadProgress.value = 1.0;

      showSuccessToast('Vidéo ajoutée avec succès !');
      await Future.delayed(const Duration(milliseconds: 500));

      Get.offAllNamed('/main', arguments: 0);
    } catch (e) {
      Get.snackbar('Erreur Téléversement', '$e', backgroundColor: Colors.redAccent, colorText: Colors.white);
    } finally {
      resetUploadState();
    }
  }

  Future<bool> _safeUploadFile({
    required File file,
    required Reference storageRef,
    required Function(double) onProgress,
  }) async {
    try {
      final metadata = SettableMetadata(
        contentType: 'video/mp4',
        cacheControl: 'public,max-age=3600',
      );

      final uploadTask = storageRef.putFile(file, metadata);
      _currentUploadTask = uploadTask;
      final completer = Completer<bool>();

      uploadTask.snapshotEvents.listen((snapshot) async {
        if (snapshot.state == TaskState.running) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(progress);

          if (!_internetAvailable) {
            await uploadTask.pause();
            Get.snackbar('Connexion perdue', 'Upload en pause...', backgroundColor: Colors.orangeAccent, colorText: Colors.white);
          }
        } else if (snapshot.state == TaskState.paused && _internetAvailable) {
          await uploadTask.resume();
        } else if (snapshot.state == TaskState.success) {
          completer.complete(true);
        } else if (snapshot.state == TaskState.error) {
          completer.complete(false);
        }
      }, onError: (e) {
        completer.complete(false);
      });

      return await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => false,
      );
    } catch (e) {
      return false;
    }
  }

  void cancelUpload() {
    _currentUploadTask?.cancel();
    VideoCompress.cancelCompression();
    resetUploadState();
    if (Get.isDialogOpen == true) {
      Get.back();
    }
    Get.snackbar('Annulé', 'Téléversement annulé.', backgroundColor: Colors.orangeAccent, colorText: Colors.white);
  }

  void resetUploadState() {
    isUploading(false);
    uploadProgress.value = 0.0;
    uploadStage.value = '';
    selectedVideo = null;
    thumbnail = null;
    songName = null;
    caption = null;
    originalVideoPath = null;
    _currentUploadTask = null;
  }
}
