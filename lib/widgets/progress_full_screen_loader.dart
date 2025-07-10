import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/upload_video_controller.dart';

class ProgressFullScreenLoader extends StatelessWidget {
  const ProgressFullScreenLoader({super.key});

  @override
  Widget build(BuildContext context) {
    final UploadVideoController uploadController = Get.find<UploadVideoController>();

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.7),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Obx(() {
            final double progress = uploadController.uploadProgress.value;
            final String stage = uploadController.uploadStage.value;
            final bool isOptimizing = uploadController.isOptimizing.value;

            String displayedStage;
            if (isOptimizing) {
              displayedStage = 'Optimisation en cours...';
            } else if (stage.isNotEmpty) {
              displayedStage = stage;
            } else if (progress < 0.05) {
              displayedStage = 'Préparation...';
            } else if (progress < 0.25) {
              displayedStage = 'Compression...';
            } else if (progress < 0.65) {
              displayedStage = 'Téléversement Vidéo...';
            } else if (progress < 1.0) {
              displayedStage = 'Téléversement Miniature...';
            } else {
              displayedStage = 'Finalisation...';
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayedStage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF214D4F),
                  ),
                ),
                const SizedBox(height: 20),
                if (!isOptimizing) ...[
                  LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: Colors.grey[300],
                    color: const Color(0xFF214D4F),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: uploadController.cancelUpload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    icon: const Icon(Icons.cancel, color: Colors.white),
                    label: const Text(
                      "Annuler",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ] else ...[
                  const CircularProgressIndicator(color: Color(0xFF214D4F)),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}
