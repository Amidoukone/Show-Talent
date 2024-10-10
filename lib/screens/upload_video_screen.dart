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
        title: const Text(
          'Ajouter une vidéo',
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF214D4F),
        centerTitle: true,  // Centrer le titre pour un effet plus élégant
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icône représentant une caméra/galerie pour un aspect plus visuel
              const Icon(Icons.video_collection, size: 80, color: Color(0xFF214D4F)),
              const SizedBox(height: 30),

              // Texte d'instruction
              const Text(
                'Sélectionnez la source de votre vidéo',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Bouton pour choisir une vidéo depuis la galerie
              ElevatedButton.icon(
                onPressed: () => _pickVideo(ImageSource.gallery),
                icon: const Icon(Icons.photo_library, color: Colors.white),
                label: const Text(
                  'Galerie',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF214D4F),  // Couleur personnalisée
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),  // Coins arrondis pour un effet moderne
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // Bouton pour enregistrer une vidéo avec la caméra
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
          ),
        ),
      ),
    );
  }
}
