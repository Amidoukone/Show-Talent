import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:video_compress/video_compress.dart';

class UploadVideoController extends GetxController {
  var isUploading = false.obs;
  var uploadProgress = 0.0.obs;

  /// Vérifie la durée maximale de la vidéo (3 minutes).
  Future<bool> isVideoDurationValid(String videoPath) async {
    final info = await VideoCompress.getMediaInfo(videoPath);
    return (info.duration ?? 0) / 1000 <= 180; // Convertir en secondes
  }

  /// Vérifie la qualité de la vidéo.
  Future<bool> isVideoQualityAcceptable(String videoPath) async {
    final info = await VideoCompress.getMediaInfo(videoPath);

    // Vérification basée sur les dimensions minimales (par exemple, 720p)
    final width = info.width ?? 0;
    final height = info.height ?? 0;
    return width >= 1280 && height >= 720; // Minimum requis : HD (1280x720)
  }

  Future<File?> _compressVideo(String videoPath) async {
    try {
      final info = await VideoCompress.compressVideo(
        videoPath,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );

      if (info != null && info.file != null) {
        return info.file;
      } else {
        throw Exception("Échec de la compression vidéo");
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la compression : $e');
      return null;
    }
  }

  Future<File?> _generateThumbnail(String videoPath) async {
    try {
      final thumbnailFile = await VideoCompress.getFileThumbnail(
        videoPath,
        quality: 50,
      );

      return thumbnailFile;
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la génération de la miniature : $e');
      return null;
    }
  }

  Future<void> uploadVideo(String songName, String caption, String videoPath) async {
    File? compressedFile;
    File? thumbnailFile;

    try {
      isUploading(true);

      // Vérification de la durée de la vidéo
      if (!await isVideoDurationValid(videoPath)) {
        Get.snackbar(
          'Durée excessive',
          'La durée de la vidéo dépasse la limite de 3 minutes. Veuillez choisir une vidéo plus courte.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      // Vérification de la qualité de la vidéo
      if (!await isVideoQualityAcceptable(videoPath)) {
        Get.snackbar(
          'Qualité insuffisante',
          'La qualité de la vidéo est insuffisante. Veuillez choisir une vidéo de meilleure qualité.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      compressedFile = await _compressVideo(videoPath);
      if (compressedFile == null) throw Exception("Échec de la compression vidéo");

      thumbnailFile = await _generateThumbnail(videoPath);
      if (thumbnailFile == null) throw Exception("Échec de la génération de la miniature");

      String videoFileName = basename(compressedFile.path);
      String thumbnailFileName = 'thumbnail_$videoFileName';

      Reference videoRef = FirebaseStorage.instance.ref().child('videos/$videoFileName');
      Reference thumbnailRef = FirebaseStorage.instance.ref().child('thumbnails/$thumbnailFileName');

      // Écouter le téléversement de la vidéo
      UploadTask videoUploadTask = videoRef.putFile(compressedFile);
      videoUploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        uploadProgress.value = snapshot.bytesTransferred / snapshot.totalBytes;
      });

      String videoUrl = await (await videoUploadTask).ref.getDownloadURL();
      String thumbnailUrl = await (await thumbnailRef.putFile(thumbnailFile)).ref.getDownloadURL();

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
        'Votre vidéo a été téléchargée avec succès !',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF214D4F),
        colorText: Colors.white,
        margin: const EdgeInsets.all(10),
        borderRadius: 8,
      );

      Get.offAllNamed('/home');
    } catch (e) {
      Get.snackbar('Erreur', 'Échec du téléchargement : $e');
    } finally {
      isUploading(false);
      uploadProgress.value = 0.0;
    }
  }
}
