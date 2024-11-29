import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:show_talent/controller/upload_video_controller.dart';
import 'upload_form.dart';

class UploadVideoScreen extends StatefulWidget {
  const UploadVideoScreen({super.key});

  @override
  State<UploadVideoScreen> createState() => _UploadVideoScreenState();
}

class _UploadVideoScreenState extends State<UploadVideoScreen> {
  final ImagePicker _picker = ImagePicker();
  RxBool isLoading = false.obs; // Gestion de l'état pour l'animation de chargement
  final UploadVideoController _uploadController = Get.put(UploadVideoController());

  Future<void> _pickVideo(ImageSource source) async {
    try {
      isLoading(true);
      final pickedFile = await _picker.pickVideo(source: source);
      isLoading(false);

      if (pickedFile != null) {
        Get.to(() => UploadForm(videoFile: File(pickedFile.path), videoPath: pickedFile.path));
      } else {
        Get.snackbar('Erreur', 'Aucune vidéo sélectionnée');
      }
    } catch (e) {
      isLoading(false);
      Get.snackbar('Erreur', 'Échec de la sélection de la vidéo : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ajouter une vidéo',
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF214D4F),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
          child: Obx(() {
            if (isLoading.value || _uploadController.isUploading.value) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _uploadController.uploadProgress.value,
                    color: const Color(0xFF214D4F),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Téléversement en cours : ${(_uploadController.uploadProgress.value * 100).toInt()}%',
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                ],
              );
            }

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.video_collection, size: 80, color: Color(0xFF214D4F)),
                const SizedBox(height: 30),
                const Text(
                  'Sélectionnez la source de votre vidéo',
                  style: TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => _pickVideo(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library, color: Colors.white),
                  label: const Text(
                    'Galerie',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF214D4F),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  onPressed: () => _pickVideo(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  label: const Text(
                    'Caméra',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF214D4F),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
