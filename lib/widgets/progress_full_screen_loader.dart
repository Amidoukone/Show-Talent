import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/upload_video_controller.dart';
import 'package:adfoot/theme/ad_colors.dart';

class ProgressFullScreenLoader extends StatelessWidget {
  const ProgressFullScreenLoader({
    super.key,
    required this.uploadController,
  });

  final UploadVideoController uploadController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ Remplacement de withOpacity par withValues(alpha: ...)
      backgroundColor: Colors.black.withValues(alpha: 0.7),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 30),
          decoration: BoxDecoration(
            color: AdColors.surfaceCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AdColors.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Obx(() {
            // Sécurisation légère: évite une valeur non-finie qui casserait l’affichage
            final double rawProgress = uploadController.uploadProgress.value;
            final double progress = rawProgress.isFinite ? rawProgress : 0.0;

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
                    color: AdColors.onSurface,
                  ),
                ),
                const SizedBox(height: 20),
                if (!isOptimizing) ...[
                  LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: AdColors.surfaceAlt,
                    color: AdColors.brand,
                    minHeight: 8,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${(progress.clamp(0.0, 1.0) * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AdColors.onSurfaceMuted,
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: uploadController.cancelUpload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                    ),
                    icon: const Icon(Icons.cancel, color: Colors.white),
                    label: const Text(
                      "Annuler",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ] else ...[
                  const CircularProgressIndicator(color: AdColors.brand),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}
