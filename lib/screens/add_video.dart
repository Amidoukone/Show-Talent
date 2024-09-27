import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart'; // Pour sélectionner une vidéo
import 'dart:io';

import '../controller/upload_video_controller.dart';

class AddVideo extends StatefulWidget {
  const AddVideo({super.key});

  @override
  _AddVideoState createState() => _AddVideoState();
}

class _AddVideoState extends State<AddVideo> {
  final UploadVideoController uploadVideoController = Get.put(UploadVideoController());
  final TextEditingController songController = TextEditingController();
  final TextEditingController captionController = TextEditingController();
  File? _videoFile;

  Future<void> _pickVideo() async {
    final pickedFile = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _videoFile = File(pickedFile.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter une vidéo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: songController,
              decoration: const InputDecoration(
                labelText: 'Nom de la chanson',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: captionController,
              decoration: const InputDecoration(
                labelText: 'Légende',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _pickVideo,
              child: const Text('Sélectionner une vidéo'),
            ),
            const SizedBox(height: 20),
            if (_videoFile != null)
              Text('Vidéo sélectionnée : ${_videoFile!.path}'),
            const SizedBox(height: 20),
            Obx(() {
              if (uploadVideoController.isUploading.value) {
                return const CircularProgressIndicator();
              }
              return ElevatedButton(
                onPressed: () {
                  if (_videoFile != null) {
                    uploadVideoController.uploadVideo(
                      songController.text,
                      captionController.text,
                      _videoFile!.path,
                    );
                  } else {
                    Get.snackbar('Erreur', 'Veuillez sélectionner une vidéo d\'abord');
                  }
                },
                child: const Text('Télécharger la vidéo'),
              );
            }),
          ],
        ),
      ),
    );
  }
}
