import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/upload_video_controller.dart';

class UploadForm extends StatefulWidget {
  final File videoFile;
  final String videoPath;

  const UploadForm({super.key, required this.videoFile, required this.videoPath});

  @override
  State<UploadForm> createState() => _UploadFormState();
}

class _UploadFormState extends State<UploadForm> {
  final UploadVideoController uploadVideoController = Get.put(UploadVideoController());
  final TextEditingController songController = TextEditingController();
  final TextEditingController captionController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Téléverser une vidéo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: songController,
              decoration: const InputDecoration(labelText: 'Nom de la chanson'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: captionController,
              decoration: const InputDecoration(labelText: 'Légende'),
            ),
            const SizedBox(height: 20),
            Obx(() {
              if (uploadVideoController.isUploading.value) {
                return const CircularProgressIndicator();
              }
              return ElevatedButton(
                onPressed: () {
                  if (songController.text.isNotEmpty && captionController.text.isNotEmpty) {
                    uploadVideoController.uploadVideo(
                      songController.text,
                      captionController.text,
                      widget.videoPath,
                    );
                    Get.back(); // Retour après téléversement
                  } else {
                    Get.snackbar('Erreur', 'Veuillez remplir tous les champs');
                  }
                },
                child: const Text('Téléverser la vidéo'),
              );
            }),
          ],
        ),
      ),
    );
  }
}
