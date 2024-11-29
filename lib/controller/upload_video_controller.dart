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

      // Afficher un message de succès avec personnalisation
      Get.snackbar(
        'Succès',
        'Votre vidéo a été téléchargée avec succès !',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF214D4F), // Couleur de fond personnalisée
        colorText: Colors.white, // Texte en blanc pour la lisibilité
        margin: const EdgeInsets.all(10),
        borderRadius: 8,
      );

      // Redirection vers HomeScreen après le succès
      Get.offAllNamed('/home');
    } catch (e) {
      Get.snackbar('Erreur', 'Échec du téléchargement : $e');
    } finally {
      isUploading(false);
      uploadProgress.value = 0.0;
    }
  }
}
