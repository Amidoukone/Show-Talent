import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/upload_video_controller.dart';
import 'package:video_player/video_player.dart';

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
  late VideoPlayerController _videoPlayerController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    songController.dispose();
    captionController.dispose();
    super.dispose();
  }

  /// Initialisation du lecteur vidéo.
  void _initializeVideoPlayer() {
    _videoPlayerController = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        setState(() {});
      }).catchError((e) {
        Get.snackbar(
          'Erreur',
          'Échec de l\'initialisation du lecteur vidéo : $e',
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
        );
      });
  }

  /// Lecture/Pause vidéo.
  void toggleVideoPlayback() {
    if (_videoPlayerController.value.isInitialized) {
      setState(() {
        if (_isPlaying) {
          _videoPlayerController.pause();
        } else {
          _videoPlayerController.play();
        }
        _isPlaying = !_isPlaying;
      });
    }
  }

  /// Affiche un dialogue de progression pendant le téléversement.
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
        );
      }),
      barrierDismissible: false,
    );
  }

  /// Gestion de l'upload avec validation.
  Future<void> _handleUpload() async {
    if (songController.text.trim().isEmpty || captionController.text.trim().isEmpty) {
      Get.snackbar(
        'Erreur',
        'Veuillez remplir tous les champs.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      return;
    }

    // Vérifie la durée et la qualité de la vidéo avant le téléversement.
    bool isDurationValid = await uploadVideoController.isVideoDurationValid(widget.videoPath);
    bool isQualityAcceptable = await uploadVideoController.isVideoQualityAcceptable(widget.videoPath);

    if (!isDurationValid) {
      Get.snackbar(
        'Durée excessive',
        'La vidéo dépasse la durée maximale de 3 minutes. Veuillez choisir une vidéo plus courte.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orangeAccent,
        colorText: Colors.white,
      );
      return;
    }

    if (!isQualityAcceptable) {
      Get.snackbar(
        'Qualité insuffisante',
        'La qualité de la vidéo est insuffisante. Une résolution minimale de 480x360 (360p) est requise.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orangeAccent,
        colorText: Colors.white,
      );
      return;
    }

    // Affiche le dialogue de progression et lance l'upload.
    showProgressDialog();
    await uploadVideoController.uploadVideo(
      songController.text.trim(),
      captionController.text.trim(),
      widget.videoPath,
    );

    // Redirection vers l'écran d'accueil après le téléversement réussi.
    if (uploadVideoController.uploadProgress.value >= 1.0) {
      Get.back(); // Ferme le dialogue de progression
      Get.offAllNamed('/home'); // Redirection vers la page Home
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Téléverser une vidéo'),
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 200,
                color: Colors.black,
                child: _videoPlayerController.value.isInitialized
                    ? GestureDetector(
                        onTap: toggleVideoPlayback,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AspectRatio(
                              aspectRatio: _videoPlayerController.value.aspectRatio,
                              child: VideoPlayer(_videoPlayerController),
                            ),
                            if (!_isPlaying)
                              const Icon(
                                Icons.play_circle_outline,
                                color: Colors.white,
                                size: 50,
                              ),
                          ],
                        ),
                      )
                    : const Center(
                        child: CircularProgressIndicator(),
                      ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: songController,
                decoration: const InputDecoration(
                  labelText: 'Description de la vidéo',
                  filled: true,
                  fillColor: Color(0xFFE0E0E0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: captionController,
                decoration: const InputDecoration(
                  labelText: 'Légende',
                  filled: true,
                  fillColor: Color(0xFFE0E0E0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Obx(() {
                if (uploadVideoController.isUploading.value) {
                  return const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF214D4F)),
                  );
                }
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF214D4F),
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                  ),
                  onPressed: _handleUpload,
                  child: const Text(
                    'Téléverser la vidéo',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
