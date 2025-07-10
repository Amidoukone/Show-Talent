import 'dart:io';
import 'package:adfoot/widgets/processing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/upload_video_controller.dart';
import 'package:adfoot/widgets/progress_full_screen_loader.dart';
import 'package:video_player/video_player.dart';

class UploadForm extends StatefulWidget {
  final File videoFile;
  final String videoPath;

  const UploadForm({
    super.key,
    required this.videoFile,
    required this.videoPath,
  });

  @override
  State<UploadForm> createState() => _UploadFormState();
}

class _UploadFormState extends State<UploadForm> {
  final UploadVideoController uploadVideoController =
      Get.find<UploadVideoController>();
  final TextEditingController songController = TextEditingController();
  final TextEditingController captionController = TextEditingController();
  late VideoPlayerController _videoPlayerController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _videoPlayerController = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) => setState(() {}));
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    songController.dispose();
    captionController.dispose();
    super.dispose();
  }

  void toggleVideoPlayback() {
    if (_videoPlayerController.value.isInitialized) {
      setState(() {
        _isPlaying
            ? _videoPlayerController.pause()
            : _videoPlayerController.play();
        _isPlaying = !_isPlaying;
      });
    }
  }

  Future<void> _handleUpload() async {
    final song = songController.text.trim();
    final caption = captionController.text.trim();

    if (song.isEmpty || caption.isEmpty) {
      Get.snackbar('Erreur', 'Veuillez remplir tous les champs.',
          backgroundColor: Colors.redAccent, colorText: Colors.white);
      return;
    }

    Get.dialog(
      const ProgressFullScreenLoader(),
      barrierDismissible: false,
    );

    try {
      final isReady = await uploadVideoController.prepareUpload(
        song: song,
        cap: caption,
        videoPath: widget.videoPath,
      );

      if (isReady) {
        await uploadVideoController.uploadDirectly();
      } else {
        if (Get.isDialogOpen == true) {
          Get.back(); // Fermer si échec préparation
        }
      }
    } catch (e) {
      if (Get.isDialogOpen == true) {
        Get.back(); // Toujours fermer en cas d'erreur
      }
      Get.snackbar('Erreur', 'Erreur inattendue : $e',
          backgroundColor: Colors.redAccent, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Téléverser une vidéo'),
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: Obx(() {
        if (uploadVideoController.isOptimizing.value) {
          return const ProcessingDialog(); // Affiche "Optimisation en cours..."
        }

        if (uploadVideoController.isUploading.value) {
          return const ProgressFullScreenLoader(); // Affiche progression d'upload
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 200,
                decoration: const BoxDecoration(color: Colors.black),
                child: _videoPlayerController.value.isInitialized
                    ? GestureDetector(
                        onTap: toggleVideoPlayback,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AspectRatio(
                              aspectRatio:
                                  _videoPlayerController.value.aspectRatio,
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
                    : const Center(child: CircularProgressIndicator()),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: songController,
                decoration: const InputDecoration(
                  labelText: 'Description',
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
              ElevatedButton.icon(
                onPressed: _handleUpload,
                icon: const Icon(Icons.cloud_upload, color: Colors.white),
                label: const Text(
                  'Téléverser la vidéo',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF214D4F),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
