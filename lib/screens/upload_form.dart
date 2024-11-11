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
  bool _needsRotation = false;

  @override
  void initState() {
    super.initState();
    _videoPlayerController = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        setState(() {
          _needsRotation = _videoPlayerController.value.size.width < _videoPlayerController.value.size.height;
          _isPlaying = false;
        });
      });
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    super.dispose();
  }

  void toggleVideoPlayback() {
    setState(() {
      if (_isPlaying) {
        _videoPlayerController.pause();
      } else {
        _videoPlayerController.play();
      }
      _isPlaying = !_isPlaying;
    });
  }

  void showProgressDialog() {
    Get.dialog(
      Obx(() {
        double progressValue = uploadVideoController.uploadProgress.value;
        if (progressValue >= 1.0) {
          Future.delayed(Duration.zero, () {
            Get.back();
            Get.offAllNamed('/main');
          });
        }
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
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.rotate(
                            angle: _needsRotation ? 90 * 3.14159 / 180 : 0,
                            child: AspectRatio(
                              aspectRatio: _videoPlayerController.value.aspectRatio,
                              child: VideoPlayer(_videoPlayerController),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline,
                              color: Colors.white,
                              size: 50,
                            ),
                            onPressed: toggleVideoPlayback,
                          ),
                        ],
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: songController,
                decoration: const InputDecoration(
                  labelText: 'Description de la vidéo',
                  labelStyle: TextStyle(color: Colors.black),
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
                  labelStyle: TextStyle(color: Colors.black),
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
                  onPressed: () {
                    if (songController.text.isNotEmpty && captionController.text.isNotEmpty) {
                      showProgressDialog();
                      uploadVideoController.uploadVideo(
                        songController.text,
                        captionController.text,
                        widget.videoPath,
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
      ),
    );
  }
}
