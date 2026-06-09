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
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_surface_card.dart';

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
    // Évite double clic pendant un état actif
    if (uploadVideoController.isPreparing.value ||
        uploadVideoController.isUploading.value ||
        uploadVideoController.isOptimizing.value) {
      return;
    }

    // Validation formulaire
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Ferme les claviers avant de lancer la préparation
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
        VideoUiStrings.uploadUnexpectedErrorTitle,
        VideoUiStrings.unexpectedUploadError(e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final previewController = _videoPlayerController;

    return Scaffold(
      appBar: const AdAppBar(
        title: VideoUiStrings.uploadFormTitle,
        subtitle: 'Prévisualisation et détails',
        showBottomDivider: true,
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: AdSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Player
                      Container(
                        height: 220,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(AdRadius.lg),
                          border: Border.all(color: AdColors.divider),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: previewController != null &&
                                previewController.value.isInitialized
                            ? Stack(
                                alignment: Alignment.center,
                                children: [
                                  AspectRatio(
                                    aspectRatio:
                                        previewController.value.aspectRatio,
                                    child: VideoPlayer(previewController),
                                  ),
                                  // Bouton play/pause au centre
                                  GestureDetector(
                                    onTap: toggleVideoPlayback,
                                    child: AnimatedOpacity(
                                      opacity: _isPlaying ? 0.0 : 1.0,
                                      duration:
                                          const Duration(milliseconds: 150),
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
                                labelText: VideoUiStrings.descriptionLabel,
                                counterText: '',
                                filled: true,
                                fillColor: AdColors.surfaceCard,
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(10)),
                                ),
                                hintText: VideoUiStrings.descriptionHint,
                              ),
                              validator: (val) {
                                final v = (val ?? '').trim();
                                if (v.isEmpty) {
                                  return VideoUiStrings.descriptionRequired;
                                }
                                if (v.length < 3) {
                                  return VideoUiStrings.minThreeChars;
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) {
                                FocusScope.of(context)
                                    .requestFocus(_captionFocus);
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
                                labelText: VideoUiStrings.captionLabel,
                                counterText: '',
                                filled: true,
                                fillColor: AdColors.surfaceCard,
                                border: const OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(10)),
                                ),
                                hintText: VideoUiStrings.captionHint,
                              ),
                              validator: (val) {
                                final v = (val ?? '').trim();
                                if (v.isEmpty) {
                                  return VideoUiStrings.captionRequired;
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
                      AdButton(
                        onPressed: isBusy ? null : _handleUpload,
                        leading: Icons.cloud_upload_rounded,
                        label: VideoUiStrings.uploadVideoButton,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        VideoUiStrings.uploadReminder,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.7),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
