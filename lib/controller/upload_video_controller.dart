import 'dart:async';
import 'dart:io';
import 'package:adfoot/controller/video_controller.dart';
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
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((resultList) {
      final result = resultList.firstOrNull;
      _internetAvailable = result != null && result != ConnectivityResult.none;
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

      if (!isValidDuration || !isValidQuality) {
        Get.back();
        Get.snackbar(
          'Erreur',
          isValidDuration ? 'Qualité vidéo insuffisante (minimum 360p).' : 'La durée dépasse 60 secondes.',
          backgroundColor: Colors.orangeAccent,
          colorText: Colors.white,
        );
        return false;
      }

      uploadStage.value = "Compression vidéo...";
      uploadProgress.value = 0.05;

      _compressionSubscription?.unsubscribe();
      _compressionSubscription = VideoCompress.compressProgress$.subscribe((progress) {
        if (progress < 100) {
          uploadProgress.value = 0.05 + (progress * 0.2 / 100);
        }
      });

      final compressed = await VideoTools.compressVideoSilently(videoPath);
      _compressionSubscription?.unsubscribe();

      selectedVideo = compressed ?? File(videoPath);
      uploadProgress.value = compressed == null ? 0.15 : 0.25;

      // Tentatives robustes de génération de miniature
      thumbnail = await VideoTools.generateThumbnail(videoPath);
      if (thumbnail == null) {
        await Future.delayed(const Duration(milliseconds: 800));
        thumbnail = await VideoTools.generateThumbnail(videoPath);
      }
      if (thumbnail == null) {
        await Future.delayed(const Duration(milliseconds: 1200));
        thumbnail = await VideoTools.generateThumbnail(videoPath);
      }

      if (thumbnail == null) {
        Get.back();
        Get.snackbar('Erreur', 'Erreur génération miniature après plusieurs tentatives.', backgroundColor: Colors.redAccent, colorText: Colors.white);
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

    if (!_internetAvailable) {
      Get.snackbar('Connexion lente', 'Nous allons essayer de continuer malgré la connexion faible.', backgroundColor: Colors.orangeAccent, colorText: Colors.white);
    }

    final videoId = const Uuid().v4();
    final videoPath = 'videos/$videoId.mp4';
    final thumbPath = 'thumbnails/thumbnail_$videoId.jpg';

    final videoRef = FirebaseStorage.instance.ref().child(videoPath);
    final thumbRef = FirebaseStorage.instance.ref().child(thumbPath);

    try {
      final videoUploaded = await _safeUploadFile(
        file: selectedVideo!,
        storageRef: videoRef,
        onProgress: (p) => uploadProgress.value = 0.3 + (0.35 * p),
      );

      if (!videoUploaded) {
        Get.snackbar('Erreur Téléversement', 'Échec upload vidéo.', backgroundColor: Colors.redAccent, colorText: Colors.white);
        resetUploadState();
        return;
      }

      final thumbUploaded = await _safeUploadFile(
        file: thumbnail!,
        storageRef: thumbRef,
        onProgress: (p) => uploadProgress.value = 0.65 + (0.35 * p),
      );

      if (!thumbUploaded) {
        Get.snackbar('Erreur Téléversement', 'Échec upload miniature.', backgroundColor: Colors.redAccent, colorText: Colors.white);
        resetUploadState();
        return;
      }

      final videoDownloadUrl = await videoRef.getDownloadURL();
      final thumbDownloadUrl = await thumbRef.getDownloadURL();

      final user = Get.find<UserController>().user;
      final now = Timestamp.now();

      await FirebaseFirestore.instance.collection('videos').doc(videoId).set({
        'id': videoId,
        'videoUrl': videoDownloadUrl,
        'thumbnail': thumbDownloadUrl,
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
      });

      uploadProgress.value = 1.0;

      await _waitForVideoStatusReady(videoId);

      final doc = await FirebaseFirestore.instance.collection('videos').doc(videoId).get();
      if ((doc.data()?['status'] ?? '') != 'ready') {
        Get.snackbar(
          'Vidéo en traitement',
          'La vidéo est en cours d’optimisation et sera visible sous peu.',
          backgroundColor: Colors.orangeAccent,
          colorText: Colors.white,
        );
      } else {
        final videoController = Get.isRegistered<VideoController>() ? Get.find<VideoController>() : null;
        if (videoController != null) {
          await videoController.refreshVideos();
        }

        showSuccessToast('Vidéo ajoutée avec succès !');
        await Future.delayed(const Duration(milliseconds: 500));
        Get.offAllNamed('/main', arguments: 0);
      }
    } catch (e) {
      Get.snackbar('Erreur Téléversement', '$e', backgroundColor: Colors.redAccent, colorText: Colors.white);
    } finally {
      resetUploadState();
    }
  }

  // Reste inchangé
  Future<void> _waitForVideoStatusReady(String videoId) async {
    Get.dialog(
      const _ProcessingDialog(),
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
    );

    const timeout = Duration(minutes: 2);
    final start = DateTime.now();

    while (DateTime.now().difference(start) < timeout) {
      try {
        final doc = await FirebaseFirestore.instance.collection('videos').doc(videoId).get();
        final status = doc.data()?['status'];
        final optimized = doc.data()?['optimized'] ?? false;

        if (status == 'ready' && optimized == true) {
          break;
        }
      } catch (_) {}

      await Future.delayed(const Duration(seconds: 2));
    }

    if (Get.isDialogOpen ?? false) Get.back();
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

      return await completer.future.timeout(const Duration(minutes: 3), onTimeout: () => false);
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

// ⬇️ Classe de chargement pendant optimisation
class _ProcessingDialog extends StatefulWidget {
  const _ProcessingDialog();

  @override
  State<_ProcessingDialog> createState() => _ProcessingDialogState();
}

class _ProcessingDialogState extends State<_ProcessingDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<int> _dotAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();

    _dotAnimation = StepTween(begin: 1, end: 3).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String getDots(int count) => List.generate(count, (_) => '.').join();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedBuilder(
          animation: _dotAnimation,
          builder: (context, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 12),
                Text(
                  "Optimisation en cours${getDots(_dotAnimation.value)}",
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
