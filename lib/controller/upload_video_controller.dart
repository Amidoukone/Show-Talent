import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:show_talent/controller/user_controller.dart'; // Pour obtenir l'utilisateur actuel

class UploadVideoController extends GetxController {
  var isUploading = false.obs;

  // Méthode pour téléverser une vidéo
  Future<void> uploadVideo(String songName, String caption, String videoPath) async {
    if (songName.isEmpty || caption.isEmpty) {
      Get.snackbar('Erreur', 'Le nom de la chanson et la légende ne peuvent pas être vides');
      return;
    }

    try {
      isUploading(true);  // Indique que le téléchargement commence
      File videoFile = File(videoPath);

      // Générer un nom unique pour la vidéo dans Firebase Storage
      String fileName = basename(videoPath);
      Reference storageRef = FirebaseStorage.instance.ref().child('videos/$fileName');

      // Téléverser la vidéo dans Firebase Storage
      UploadTask uploadTask = storageRef.putFile(videoFile);
      TaskSnapshot snapshot = await uploadTask;

      // Récupérer l'URL de la vidéo depuis Firebase Storage
      String videoUrl = await snapshot.ref.getDownloadURL();
      print('URL de la vidéo téléchargée : $videoUrl'); // Log pour vérifier l'URL

      // Générer un ID unique pour la vidéo dans Firestore
      String videoId = FirebaseFirestore.instance.collection('videos').doc().id;

      // Sauvegarder les métadonnées de la vidéo dans Firestore
      await FirebaseFirestore.instance.collection('videos').doc(videoId).set({
        'id': videoId,  // Enregistrer l'ID unique de la vidéo
        'videoUrl': videoUrl,
        'songName': songName,
        'caption': caption,
        'likes': [],
        'shareCount': 0,
        'uid': Get.find<UserController>().user?.uid,  // ID de l'utilisateur
        'thumbnail': '',  // Si vous avez un générateur de miniatures, gérez-le ici
        'createdAt': FieldValue.serverTimestamp(),  // Date de création
      });

      Get.snackbar('Succès', 'Vidéo téléchargée avec succès !');
    } catch (e) {
      print('Erreur lors du téléchargement de la vidéo : $e'); // Log pour les erreurs
      Get.snackbar('Erreur', 'Une erreur est survenue pendant le téléchargement : $e');
    } finally {
      isUploading(false);  // Indique la fin du téléchargement
    }
  }
}
