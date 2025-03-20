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

  /// Miniature temporaire pour aperçu final dans snackbar
  final Rx<File?> lastGeneratedThumbnail = Rx<File?>(null);

  Future<bool> isVideoDurationValid(String videoPath) async {
    final info = await VideoCompress.getMediaInfo(videoPath);
    return (info.duration ?? 0) / 1000 <= 180;
  }

  Future<bool> isVideoQualityAcceptable(String videoPath) async {
    final info = await VideoCompress.getMediaInfo(videoPath);
    final width = info.width ?? 0;
    final height = info.height ?? 0;
    return width >= 480 && height >= 360;
  }

  Future<File?> _compressVideo(String videoPath) async {
    try {
      final info = await VideoCompress.compressVideo(
        videoPath,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );
      return info?.file;
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la compression : $e',
          backgroundColor: Colors.redAccent, colorText: Colors.white);
      return null;
    }
  }

  Future<File?> _generateThumbnail(String videoPath) async {
    try {
      final file = await VideoCompress.getFileThumbnail(videoPath, quality: 75);
      lastGeneratedThumbnail.value = file;
      return file;
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la miniature : $e',
          backgroundColor: Colors.redAccent, colorText: Colors.white);
      return null;
    }
  }

  Future<bool> _showThumbnailPreview(File thumbnailFile) async {
    return await Get.dialog<bool>(
          AlertDialog(
            title: Text('Prévisualisation de la miniature'),
            content: Image.file(thumbnailFile),
            actions: [
              TextButton(
                  onPressed: () => Get.back(result: false),
                  child: Text('Annuler')),
              TextButton(
                  onPressed: () => Get.back(result: true),
                  child: Text('Confirmer')),
            ],
          ),
        ) ??
        false;
  }

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

  Future<void> uploadVideo(
      String songName, String caption, String videoPath) async {
    File? compressedFile;
    File? thumbnailFile;

    try {
      isUploading(true);

      if (!await isVideoDurationValid(videoPath)) {
        Get.snackbar('Durée excessive', 'La vidéo dépasse 3 minutes.',
            backgroundColor: Colors.orangeAccent);
        return;
      }

      if (!await isVideoQualityAcceptable(videoPath)) {
        Get.snackbar('Qualité insuffisante', 'Minimum requis : 360p.',
            backgroundColor: Colors.orangeAccent);
        return;
      }

      final futures = await Future.wait([
        _compressVideo(videoPath),
        _generateThumbnail(videoPath),
      ]);

      compressedFile = futures[0];
      thumbnailFile = futures[1];

      if (compressedFile == null || thumbnailFile == null) {
        throw Exception("Fichiers non générés");
      }

      bool confirm = await _showThumbnailPreview(thumbnailFile);
      if (!confirm) {
        Get.snackbar('Annulé', 'Téléversement annulé',
            backgroundColor: Colors.blueAccent, colorText: Colors.white);
        return;
      }

      String videoFileName = basename(compressedFile.path);
      String thumbnailFileName = 'thumbnail_$videoFileName';

      Reference videoRef =
          FirebaseStorage.instance.ref().child('videos/$videoFileName');
      Reference thumbnailRef =
          FirebaseStorage.instance.ref().child('thumbnails/$thumbnailFileName');

      await Future.wait([
        _uploadFile(
          file: compressedFile,
          storageRef: videoRef,
          onProgress: (p) => uploadProgress.value = p / 2,
        ),
        _uploadFile(
          file: thumbnailFile,
          storageRef: thumbnailRef,
          onProgress: (p) => uploadProgress.value = 0.5 + (p / 2),
        ),
      ]);

      String videoUrl = await videoRef.getDownloadURL();
      String thumbnailUrl = await thumbnailRef.getDownloadURL();

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

      Get.snackbar('Succès', 'Vidéo téléversée avec succès !',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white);

      Get.offAllNamed('/main', arguments: 0);
    } catch (e) {
      Get.snackbar('Erreur', 'Échec du téléchargement : $e',
          backgroundColor: Colors.redAccent, colorText: Colors.white);
    } finally {
      isUploading(false);
      uploadProgress.value = 0.0;
    }
  }
}
