import 'dart:io';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:video_compress/video_compress.dart';

class UploadVideoController extends GetxController {
  var isUploading = false.obs;
  var uploadProgress = 0.0.obs;

  // Fonction pour compresser la vidéo et gérer les erreurs de compression
  Future<File?> _compressVideo(String videoPath) async {
    try {
      // Compression de la vidéo avec qualité moyenne pour un équilibre entre qualité et vitesse
      final info = await VideoCompress.compressVideo(
        videoPath,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );

      if (info != null && info.file != null) {
        print("Compression réussie : fichier compressé à ${info.file!.path}");
        return info.file;
      } else {
        throw Exception("Échec de la compression vidéo : fichier compressé introuvable.");
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la compression : $e');
      return null;
    }
  }

  // Fonction pour téléverser la vidéo compressée
  Future<void> uploadVideo(String songName, String caption, String videoPath) async {
    if (songName.isEmpty || caption.isEmpty) {
      Get.snackbar('Erreur', 'Le nom de la chanson et la légende ne peuvent pas être vides');
      return;
    }

    File? compressedFile;

    try {
      isUploading(true);
      
      // Compresser la vidéo
      compressedFile = await _compressVideo(videoPath);
      if (compressedFile == null) {
        throw Exception("Compression échouée, vidéo non disponible pour le téléversement.");
      }

      // Préparez le fichier et le chemin pour le téléversement sur Firebase
      String fileName = basename(compressedFile.path);
      Reference storageRef = FirebaseStorage.instance.ref().child('videos/$fileName');

      // Téléverser le fichier compressé et suivre la progression
      UploadTask uploadTask = storageRef.putFile(compressedFile);
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        uploadProgress.value = (snapshot.bytesTransferred / snapshot.totalBytes);
      });

      TaskSnapshot snapshot = await uploadTask;
      String videoUrl = await snapshot.ref.getDownloadURL();

      // Créer un ID unique pour la vidéo dans Firestore
      String videoId = FirebaseFirestore.instance.collection('videos').doc().id;

      // Enregistrer les métadonnées dans Firestore
      await FirebaseFirestore.instance.collection('videos').doc(videoId).set({
        'id': videoId,
        'videoUrl': videoUrl,
        'songName': songName,
        'caption': caption,
        'likes': [],
        'shareCount': 0,
        'uid': Get.find<UserController>().user?.uid,
        'thumbnail': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      Get.snackbar('Succès', 'Vidéo téléchargée avec succès !');
    } catch (e) {
      Get.snackbar('Erreur', 'Une erreur est survenue : $e');
      print("Erreur pendant le téléversement : $e");
    } finally {
      // Réinitialiser l'état d'upload
      isUploading(false);
      uploadProgress.value = 0.0;
    }
  }
}
