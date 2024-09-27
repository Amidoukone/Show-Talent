import 'package:get/get.dart';
import 'package:path/path.dart'; // Pour manipuler les chemins de fichiers

class UploadVideoController extends GetxController {
  var isUploading = false.obs;

  Future<void> uploadVideo(String songName, String caption, String videoPath) async {
    if (songName.isEmpty || caption.isEmpty) {
      Get.snackbar(
        'Erreur', 
        'Le nom de la chanson et la légende ne peuvent pas être vides',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      isUploading(true); // Indique que l'upload est en cours
      await Future.delayed(const Duration(seconds: 2)); // Simule un délai d'upload

      // Simuler l'upload (à remplacer par la vraie logique, ex. Firebase Storage)
      String fileName = basename(videoPath);
      print("Téléchargement de la vidéo : $fileName");

      // Si l'upload réussit
      Get.snackbar(
        'Succès', 
        'Vidéo téléchargée avec succès !',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      // Gestion des erreurs
      Get.snackbar(
        'Échec du téléchargement', 
        'Une erreur est survenue pendant le téléchargement',
        snackPosition: SnackPosition.BOTTOM,
      );
      print("Erreur pendant l'upload : $e");
    } finally {
      isUploading(false);
    }
  }
}
