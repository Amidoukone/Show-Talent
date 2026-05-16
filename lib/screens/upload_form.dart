import 'dart:async';
import 'dart:io';

import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:adfoot/widgets/processing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/upload_video_controller.dart';
import 'package:adfoot/widgets/progress_full_screen_loader.dart';
import 'package:video_player/video_player.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/widgets/ad_feedback.dart';

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
  late final UploadVideoController uploadVideoController;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController captionController = TextEditingController();
  final FocusNode _descriptionFocus = FocusNode();
  final FocusNode _captionFocus = FocusNode();

  VideoPlayerController? _videoPlayerController;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    uploadVideoController =
        FeatureControllerRegistry.ensureUploadVideoController();
    final controller = VideoPlayerController.file(widget.videoFile);
    _videoPlayerController = controller;
    unawaited(controller.setLooping(true).catchError((_) {}));
    unawaited(
      controller.initialize().then((_) {
        if (mounted && identical(_videoPlayerController, controller)) {
          setState(() {
            _duration = controller.value.duration;
          });
        }
      }).catchError((_) {}),
    );
  }

  @override
  void dispose() {
    unawaited(_releasePreviewController(notify: false));
    descriptionController.dispose();
    captionController.dispose();
    _descriptionFocus.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  void toggleVideoPlayback() {
    final controller = _videoPlayerController;
    if (controller != null && controller.value.isInitialized) {
      setState(() {
        if (_isPlaying) {
          unawaited(controller.pause().catchError((_) {}));
        } else {
          unawaited(controller.play().catchError((_) {}));
        }
        _isPlaying = !_isPlaying;
      });
    }
  }

  Future<void> _releasePreviewController({bool notify = true}) async {
    final controller = _videoPlayerController;
    if (controller == null) return;

    _videoPlayerController = null;
    _isPlaying = false;

    try {
      if (controller.value.isInitialized) {
        await controller.pause();
      }
    } catch (_) {}

    try {
      await controller.dispose();
    } catch (_) {}

    if (notify && mounted) {
      setState(() {});
    }
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    if (hh > 0) {
      return '${hh.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }

  Future<void> _handleUpload() async {
    // Evite double clic pendant un etat actif
    if (uploadVideoController.isPreparing.value ||
        uploadVideoController.isUploading.value ||
        uploadVideoController.isOptimizing.value) {
      return;
    }

    // Validation formulaire
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Ferme les claviers avant de lancer la preparation
    _descriptionFocus.unfocus();
    _captionFocus.unfocus();
    await _releasePreviewController();

    try {
      final isReady = await uploadVideoController.prepareUpload(
        description: descriptionController.text.trim(),
        cap: captionController.text.trim(),
        videoPath: widget.videoPath,
      );

      if (!isReady) return;

      await uploadVideoController.uploadDirectly();
    } catch (e) {
      AdFeedback.error(
        'Erreur',
        'Erreur inattendue : $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final previewController = _videoPlayerController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Téléverser une vidéo'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: Obx(() {
        final isPreparing = uploadVideoController.isPreparing.value;
        final isUploading = uploadVideoController.isUploading.value;
        final isOptimizing = uploadVideoController.isOptimizing.value;
        final isBusy = isPreparing || isUploading || isOptimizing;

        if (isOptimizing) {
          // Affiche "Optimisation en cours..."
          return const ProcessingDialog();
        }

        if (isPreparing || isUploading) {
          // Affiche progression d'upload (etapes + barre)
          return ProgressFullScreenLoader(
            uploadController: uploadVideoController,
          );
        }

        // Formulaire de saisie + previsualisation
        return GestureDetector(
          onTap: () {
            // Ferme le clavier si on tape ailleurs
            _descriptionFocus.unfocus();
            _captionFocus.unfocus();
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Player
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: previewController != null &&
                          previewController.value.isInitialized
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            AspectRatio(
                              aspectRatio: previewController.value.aspectRatio,
                              child: VideoPlayer(previewController),
                            ),
                            // Bouton play/pause au centre
                            GestureDetector(
                              onTap: toggleVideoPlayback,
                              child: AnimatedOpacity(
                                opacity: _isPlaying ? 0.0 : 1.0,
                                duration: const Duration(milliseconds: 150),
                                child: const Icon(
                                  Icons.play_circle_outline,
                                  color: Colors.white,
                                  size: 64,
                                ),
                              ),
                            ),
                            // Durée en haut à droite
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _formatDuration(_duration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : const Center(child: CircularProgressIndicator()),
                ),
                const SizedBox(height: 20),

                // Form
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        focusNode: _descriptionFocus,
                        controller: descriptionController,
                        textInputAction: TextInputAction.next,
                        maxLength: 80,
                        style: const TextStyle(color: AdColors.onSurface),
                        decoration: const InputDecoration(
                          labelText: 'Description (obligatoire)',
                          counterText: '',
                          filled: true,
                          fillColor: AdColors.surfaceCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
                          hintText: 'Ex: Dribble + frappe pied gauche',
                        ),
                        validator: (val) {
                          final v = (val ?? '').trim();
                          if (v.isEmpty) {
                            return 'La description est requise.';
                          }
                          if (v.length < 3) {
                            return 'Au moins 3 caractères.';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) {
                          FocusScope.of(context).requestFocus(_captionFocus);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        focusNode: _captionFocus,
                        controller: captionController,
                        textInputAction: TextInputAction.done,
                        maxLines: 2,
                        maxLength: 140,
                        style: const TextStyle(color: AdColors.onSurface),
                        decoration: InputDecoration(
                          labelText: 'Légende (obligatoire)',
                          counterText: '',
                          filled: true,
                          fillColor: AdColors.surfaceCard,
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
                          hintText: 'Ex: #U17 #Ailier #Vitesse',
                        ),
                        validator: (val) {
                          final v = (val ?? '').trim();
                          if (v.isEmpty) {
                            return 'La légende est requise.';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _handleUpload(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Bouton d’upload
                ElevatedButton.icon(
                  onPressed: isBusy ? null : _handleUpload,
                  icon: const Icon(Icons.cloud_upload, color: Colors.white),
                  label: const Text(
                    'Téléverser la vidéo',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdColors.brand,
                    foregroundColor: AdColors.brandOn,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      color: AdColors.brandOn,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rappel : durée max 60s • qualité minimale ≥ 480×360',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
