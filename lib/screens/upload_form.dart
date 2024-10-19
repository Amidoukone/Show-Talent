import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/push_notification.dart';
import 'package:show_talent/controller/upload_video_controller.dart';
import 'package:show_talent/screens/home_screen.dart'; // Importer l'écran d'accueil

class UploadForm extends StatefulWidget {
  final File videoFile;
  final String videoPath;

  const UploadForm(
      {super.key, required this.videoFile, required this.videoPath});

  @override
  State<UploadForm> createState() => _UploadFormState();
}

class _UploadFormState extends State<UploadForm> {
  final UploadVideoController uploadVideoController =
      Get.put(UploadVideoController());
  final TextEditingController songController = TextEditingController();
  final TextEditingController captionController = TextEditingController();

  void showProgressDialog() {
    Get.dialog(
      Obx(() {
        double progressValue = uploadVideoController.uploadProgress.value;
        return AlertDialog(
          title: const Text(
            "Téléversement en cours...",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: progressValue,
                backgroundColor: Colors.grey[300],
                color: const Color(0xFF214D4F),
              ),
              const SizedBox(height: 20),
              Text(
                "${(progressValue * 100).toStringAsFixed(2)}% terminé",
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (!uploadVideoController.isUploading.value) {
                  Get.back(); // Fermer la boîte de dialogue
                  Get.offAll(
                      () => const HomeScreen()); // Rediriger vers la page Home
                }
              },
              child: const Text(
                "Fermer",
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        );
      }),
      barrierDismissible:
          false, // Empêcher la fermeture pendant le téléversement
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Téléverser une vidéo'),
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: songController,
              decoration: const InputDecoration(
                labelText: 'Description de la vidéo',
                labelStyle: TextStyle(color: Colors.white),
                filled: true,
                fillColor: Color(0xFF2E2E2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: captionController,
              decoration: const InputDecoration(
                labelText: 'Légende',
                labelStyle: TextStyle(color: Colors.white),
                filled: true,
                fillColor: Color(0xFF2E2E2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            Obx(() {
              if (uploadVideoController.isUploading.value) {
                return const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF214D4F)),
                ); // Afficher un indicateur si en train de téléverser
              }
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF214D4F),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                ),
                onPressed: () {
                  if (songController.text.isNotEmpty &&
                      captionController.text.isNotEmpty) {
                    showProgressDialog(); // Affiche le dialogue de progression

                    uploadVideoController.uploadVideo(
                      songController.text,
                      captionController.text,
                      widget.videoPath,
                    );

                    String token =
                        "eYdOU1VrQ-2EGLg8MlgKTs:APA91bGB2ZdJ3lSo3t5ynpJZY44HrAaEAVLipvKhEzS3NyaVynTRSc_Wi2YNvmIDc7URlOmL8o8V6iz8vNTYw9XyUhakhE3CAT-dAvjRjenWH_SEemERxZfXc0AVUm0MbIU8ShwL_gMb";

                    PushNotificationService.sendNotification(
                      title: "Nouvelle vidéo uploader",
                      body: "jfnjidifjnf",
                      token: token,
                      contextType: "fhjdf",
                      contextData: widget.videoPath,
                    );
                  } else {
                    Get.snackbar(
                      'Erreur',
                      'Veuillez remplir tous les champs',
                      snackPosition: SnackPosition.BOTTOM,
                      backgroundColor: Colors.redAccent,
                      colorText: Colors.white,
                    );
                  }
                },
                child: const Text(
                  'Téléverser la vidéo',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
