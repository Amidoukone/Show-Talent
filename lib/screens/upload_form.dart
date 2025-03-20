import 'dart:io';
import 'package:adfoot/screens/full_screen_uploader.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/upload_video_controller.dart';
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
      Get.put(UploadVideoController());
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

  Future<void> _handleUpload() async {
    final song = songController.text.trim();
    final caption = captionController.text.trim();

    if (song.isEmpty || caption.isEmpty) {
      Get.snackbar(
        'Erreur',
        'Veuillez remplir tous les champs.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      return;
    }

    // Affiche l'animation plein écran
    Get.dialog(
      FullScreenUploader(progress: uploadVideoController.uploadProgress),
      barrierDismissible: false,
    );

    await uploadVideoController.uploadVideo(song, caption, widget.videoPath);

    Get.back(); // Ferme l'animation

    final thumb = uploadVideoController.lastGeneratedThumbnail.value;
    if (thumb != null) {
      Get.snackbar(
        'Vidéo ajoutée 🎉',
        'Redirection vers l\'accueil...',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.white,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
        icon: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            thumb,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
          ),
        ),
      );
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
        padding: const EdgeInsets.all(16),
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
                return const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(Color(0xFF214D4F)),
                  ),
                );
              }

              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF214D4F),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
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
    );
  }
}
