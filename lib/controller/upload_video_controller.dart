import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:video_compress/video_compress.dart';

class UploadVideoController extends GetxController {
  var isUploading = false.obs;
  var uploadProgress = 0.0.obs;

  /// Vérifie la durée maximale de la vidéo (3 minutes).
  Future<bool> isVideoDurationValid(String videoPath) async {
    final info = await VideoCompress.getMediaInfo(videoPath);
    return (info.duration ?? 0) / 1000 <= 180; // Convertir en secondes
  }

  /// Vérifie la qualité minimale de la vidéo (360p).
  Future<bool> isVideoQualityAcceptable(String videoPath) async {
    final info = await VideoCompress.getMediaInfo(videoPath);
    final width = info.width ?? 0;
    final height = info.height ?? 0;
    return width >= 480 && height >= 360; // Minimum requis : 480x360 (360p)
  }

  /// Compression vidéo optimisée.
  Future<File?> _compressVideo(String videoPath) async {
    try {
      final info = await VideoCompress.compressVideo(
        videoPath,
        quality: VideoQuality
            .MediumQuality, // Meilleur équilibre entre qualité et rapidité
        deleteOrigin: false,
      );
      return info?.file;
    } catch (e) {
      Get.snackbar(
        'Erreur',
        'Échec de la compression : $e',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      return null;
    }
  }

  /// Génération miniature optimisée.
  Future<File?> _generateThumbnail(String videoPath) async {
    try {
      return await VideoCompress.getFileThumbnail(videoPath,
          quality: 75); // Qualité optimisée
    } catch (e) {
      Get.snackbar(
        'Erreur',
        'Échec de la génération de la miniature : $e',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      return null;
    }
  }

  /// Téléversement avec affichage de progression.
  Future<void> _uploadFile({
    required File file,
    required Reference storageRef,
    required Function(double) onProgress,
  }) async {
    final uploadTask = storageRef.putFile(file);

    uploadTask.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress(progress);
      }
    });

    await uploadTask;
  }

  /// Téléversement vidéo avec optimisation.
  Future<void> uploadVideo(
      String songName, String caption, String videoPath) async {
    File? compressedFile;
    File? thumbnailFile;

    try {
      isUploading(true);

      // Vérification de la vidéo avant téléversement
      if (!await isVideoDurationValid(videoPath)) {
        Get.snackbar(
          'Durée excessive',
          'La vidéo dépasse la limite de 3 minutes. Veuillez choisir une vidéo plus courte.',
          backgroundColor: Colors.orangeAccent,
        );
        return;
      }

      if (!await isVideoQualityAcceptable(videoPath)) {
        Get.snackbar(
          'Qualité insuffisante',
          'La qualité est insuffisante. Une qualité minimum de 360p est requise.',
          backgroundColor: Colors.orangeAccent,
        );
        return;
      }

      // Compression et génération de miniature
      final futures = await Future.wait([
        _compressVideo(videoPath),
        _generateThumbnail(videoPath),
      ]);

      compressedFile = futures[0];
      thumbnailFile = futures[1];

      if (compressedFile == null) throw Exception("Compression échouée");
      if (thumbnailFile == null)
        throw Exception("Génération de miniature échouée");

      String videoFileName = basename(compressedFile.path);
      String thumbnailFileName = 'thumbnail_$videoFileName';

      Reference videoRef =
          FirebaseStorage.instance.ref().child('videos/$videoFileName');
      Reference thumbnailRef =
          FirebaseStorage.instance.ref().child('thumbnails/$thumbnailFileName');

      // Téléversement avec progression
      await Future.wait([
        _uploadFile(
          file: compressedFile,
          storageRef: videoRef,
          onProgress: (progress) {
            uploadProgress.value = progress / 2; // 50% pour la vidéo
          },
        ),
        _uploadFile(
          file: thumbnailFile,
          storageRef: thumbnailRef,
          onProgress: (progress) {
            uploadProgress.value =
                0.5 + (progress / 2); // 50-100% pour la miniature
          },
        ),
      ]);

      String videoUrl = await videoRef.getDownloadURL();
      String thumbnailUrl = await thumbnailRef.getDownloadURL();

      // Sauvegarde des métadonnées dans Firestore
      String videoId = FirebaseFirestore.instance.collection('videos').doc().id;
      await FirebaseFirestore.instance.collection('videos').doc(videoId).set({
        'id': videoId,
        'videoUrl': videoUrl,
        'thumbnail': thumbnailUrl,
        'songName': songName,
        'caption': caption,
        'likes': [],
        'shareCount': 0,
        'uid': Get.find<UserController>().user?.uid,
        'profilePhoto': Get.find<UserController>().user?.photoProfil,
        'createdAt': FieldValue.serverTimestamp(),
      });

      Get.snackbar(
        'Succès',
        'Vidéo téléversée avec succès !',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );

      Get.offAllNamed('/home');
    } catch (e) {
      Get.snackbar(
        'Erreur',
        'Échec du téléchargement : $e',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    } finally {
      isUploading(false);
      uploadProgress.value = 0.0;
    }
  }
}
