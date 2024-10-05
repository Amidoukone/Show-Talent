import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'upload_form.dart';  // Formulaire pour le téléversement de la vidéo

class UploadVideoScreen extends StatefulWidget {
  const UploadVideoScreen({super.key});

  @override
  State<UploadVideoScreen> createState() => _UploadVideoScreenState();
}

class _UploadVideoScreenState extends State<UploadVideoScreen> {
  final ImagePicker _picker = ImagePicker();

  // Fonction pour choisir une vidéo depuis la galerie ou l'appareil photo
  Future<void> _pickVideo(ImageSource source) async {
    final pickedFile = await _picker.pickVideo(source: source);
    if (pickedFile != null) {
      // Redirection vers un formulaire de téléversement avec la vidéo sélectionnée
      Get.to(() => UploadForm(videoFile: File(pickedFile.path), videoPath: pickedFile.path));
    } else {
      Get.snackbar('Erreur', 'Aucune vidéo sélectionnée');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter une vidéo',
        style: TextStyle(fontSize: 16, color: Colors.white),),
        
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => _pickVideo(ImageSource.gallery),
              child: const Text('Sélectionner une vidéo depuis la galerie',
              style: TextStyle(fontSize: 16, color: Colors.white),),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => _pickVideo(ImageSource.camera),
              child: const Text('Enregistrer une vidéo',
              style: TextStyle(fontSize: 16, color: Colors.white),),
            ),
          ],
        ),
      ),
    );
  }
}
