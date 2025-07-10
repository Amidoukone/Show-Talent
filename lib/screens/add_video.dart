import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:adfoot/controller/upload_video_controller.dart';
import 'upload_form.dart';

class AddVideo extends StatefulWidget {
  const AddVideo({super.key});

  @override
  State<AddVideo> createState() => _AddVideoState();
}

class _AddVideoState extends State<AddVideo> {
  final UploadVideoController uploadVideoController =
      Get.put(UploadVideoController());
  final ImagePicker _picker = ImagePicker();
  final RxBool isLoading = false.obs;

  Future<void> _pickVideo(ImageSource source) async {
    try {
      isLoading.value = true;
      final pickedFile = await _picker.pickVideo(source: source);
      isLoading.value = false;

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        Get.to(() => UploadForm(videoFile: file, videoPath: pickedFile.path));
      } else {
        Get.snackbar('Erreur', 'Aucune vidéo sélectionnée',
            backgroundColor: Colors.redAccent, colorText: Colors.white);
      }
    } catch (e) {
      isLoading.value = false;
      Get.snackbar('Erreur', 'Échec lors de la sélection : $e',
          backgroundColor: Colors.redAccent, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter une vidéo'),
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: Obx(() {
        // Affichage pendant le chargement initial ou le téléversement
        if (isLoading.value || uploadVideoController.isUploading.value) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  value: uploadVideoController.uploadProgress.value,
                  color: const Color(0xFF214D4F),
                ),
                const SizedBox(height: 20),
                Text(
                  'Téléversement en cours : ${(uploadVideoController.uploadProgress.value * 100).toInt()}%',
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ],
            ),
          );
        }

        // Affichage pendant l'optimisation
        if (uploadVideoController.isOptimizing.value) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFF214D4F)),
                SizedBox(height: 20),
                Text(
                  'Optimisation en cours...',
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ],
            ),
          );
        }

        // État par défaut : sélection de la source vidéo
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.video_collection,
                  size: 80, color: Color(0xFF214D4F)),
              const SizedBox(height: 30),
              const Text(
                'Sélectionnez la source de votre vidéo',
                style: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _pickVideo(ImageSource.gallery),
                icon: const Icon(Icons.photo_library, color: Colors.white),
                label: const Text('Galerie',
                    style: TextStyle(fontSize: 16, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF214D4F),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 30),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
              const SizedBox(height: 15),
              ElevatedButton.icon(
                onPressed: () => _pickVideo(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, color: Colors.white),
                label: const Text('Caméra',
                    style: TextStyle(fontSize: 16, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF214D4F),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 30),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
