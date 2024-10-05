import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import '../controller/upload_video_controller.dart';

class ConfirmScreen extends StatefulWidget {
  final File videoFile;
  final String videoPath;

  const ConfirmScreen({
    super.key,
    required this.videoFile,
    required this.videoPath,
  });

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  late VideoPlayerController _controller;
  final TextEditingController _songController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();
  final UploadVideoController uploadVideoController = Get.put(UploadVideoController());

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile);
    _controller.initialize().then((_) {
      setState(() {});
      _controller.play();
      _controller.setLooping(true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _songController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 30),
            if (_controller.value.isInitialized)
              SizedBox(
                width: MediaQuery.of(context).size.width,
                height: 400,
                child: VideoPlayer(_controller),
              ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  TextField(
                    controller: _songController,
                    decoration: InputDecoration(
                      labelText: 'Nom de la chanson',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _captionController,
                    decoration: InputDecoration(
                      labelText: 'Légende',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Obx(() {
                    return ElevatedButton(
                      onPressed: uploadVideoController.isUploading.value
                          ? null
                          : () {
                              uploadVideoController.uploadVideo(
                                _songController.text,
                                _captionController.text,
                                widget.videoPath,
                              );
                            },
                      child: uploadVideoController.isUploading.value
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Partager'),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
