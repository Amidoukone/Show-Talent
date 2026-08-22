// lib/screens/add_video.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'package:adfoot/controller/upload_video_controller.dart';
import 'upload_form.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/adfoot_support.dart';
import 'package:adfoot/utils/video_publication_quota.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_surface_card.dart';
import 'success_toast.dart';

class AddVideo extends StatefulWidget {
  const AddVideo({super.key});

  @override
  State<AddVideo> createState() => _AddVideoState();
}

class _AddVideoState extends State<AddVideo> {
  final UploadVideoController uploadVideoController =
      FeatureControllerRegistry.ensureUploadVideoController();

  final ImagePicker _picker = ImagePicker();
  final RxBool isLoading = false.obs;

  /// Explains that the account is at its publication cap, and offers the only
  /// action that actually lifts it.
  ///
  /// The server already refuses the upload, but it refuses it at
  /// `createUploadSession` — after the clip has been chosen, trimmed and
  /// thumbnailed — with "Archivez une video avant d'en ajouter une nouvelle",
  /// an instruction this application offers no way to follow. Both problems
  /// are answered here: the refusal arrives before any work, and it points at
  /// the agency.
  Future<void> _showPublicationQuotaNotice() async {
    final wantsContact = await AdDialogs.confirm(
      context: context,
      title: VideoUiStrings.uploadQuotaReachedTitle,
      message: VideoUiStrings.uploadQuotaReachedMessage(
        VideoPublicationQuota.maxPublishedVideos,
      ),
      confirmLabel: VideoUiStrings.uploadQuotaContactAction,
      cancelLabel: VideoUiStrings.uploadQuotaDismissAction,
    );

    if (!wantsContact) return;

    final opened = await AdfootSupport.openWhatsApp();
    if (opened || !mounted) return;

    AdFeedback.info(
      VideoUiStrings.uploadQuotaReachedTitle,
      VideoUiStrings.uploadQuotaContactFallback(
        AdfootSupport.phoneDisplay,
        AdfootSupport.website,
      ),
      duration: const Duration(seconds: 6),
    );
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      isLoading.value = true;

      final quota = await uploadVideoController.checkPublicationQuota();
      if (!mounted) {
        isLoading.value = false;
        return;
      }
      if (quota == VideoPublicationQuotaState.exhausted) {
        isLoading.value = false;
        await _showPublicationQuotaNotice();
        return;
      }

      // Galerie uniquement (caméra désactivée)
      final pickedFile = await _picker.pickVideo(source: ImageSource.gallery);

      isLoading.value = false;

      if (pickedFile == null) {
        showInfoToast(VideoUiStrings.noVideoSelected);
        return;
      }

      final file = File(pickedFile.path);
      // Navigation vers le formulaire d’upload
      Get.to(() => UploadForm(videoFile: file, videoPath: pickedFile.path));
    } on PlatformException catch (e) {
      isLoading.value = false;
      // Gestion permission/refus galerie
      AdFeedback.warning(
        VideoUiStrings.galleryPermissionTitle,
        VideoUiStrings.galleryPermissionDetails(e),
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      isLoading.value = false;
      AdFeedback.error(
        VideoUiStrings.videoSelectionErrorTitle,
        VideoUiStrings.videoSelectionFailed(e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: const AdAppBar(
        title: VideoUiStrings.addVideoScreenTitle,
        subtitle: VideoUiStrings.addVideoScreenSubtitle,
        showBottomDivider: true,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: cs.surface,
        child: SafeArea(
          child: Obx(() {
            final preparing = uploadVideoController.isPreparing.value;
            final uploading = uploadVideoController.isUploading.value;
            final optimizing = uploadVideoController.isOptimizing.value;
            final loading = isLoading.value;

            // Contenu principal
            final content = _BodyCard(onPick: _pickVideoFromGallery);

            // Superpose un overlay "verre dépoli" quand on charge / prépare /
            // upload / optimise. isPreparing doit être inclus: sans lui, un
            // retour en arrière pendant la préparation (trim/miniature) sur
            // UploadForm ramène ici sans aucune indication qu'un traitement
            // est toujours en cours en arrière-plan.
            final showOverlay = loading || preparing || uploading || optimizing;

            return Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AdSpacing.md,
                    AdSpacing.lg,
                    AdSpacing.md,
                    AdSpacing.xxl,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: content,
                      ),
                    ),
                  ),
                ),
                if (showOverlay)
                  _ProgressOverlay(
                    controller: uploadVideoController,
                    waiting: loading,
                    preparing: preparing,
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// Carte principale avec bouton “Choisir depuis la galerie”
class _BodyCard extends StatelessWidget {
  final VoidCallback onPick;

  const _BodyCard({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return AdSurfaceCard(
      padding: const EdgeInsets.all(AdSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Illustration cercle + icône
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AdColors.brand.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(AdRadius.xl),
              border: Border.all(color: AdColors.brand.withValues(alpha: .24)),
            ),
            child: const Center(
              child: Icon(
                Icons.video_library_rounded,
                size: 42,
                color: AdColors.brand,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            VideoUiStrings.addVideoPickTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 18,
              letterSpacing: .2,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            VideoUiStrings.uploadConstraintsHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: AdColors.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 22),

          AdButton(
            label: VideoUiStrings.chooseFromGallery,
            leading: Icons.photo_library_rounded,
            onPressed: onPick,
          ),

          const SizedBox(height: 14),

          // Tips + puces
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _TipChip(
                icon: Icons.timer_rounded,
                label: VideoUiStrings.maxDurationChip,
              ),
              _TipChip(
                icon: Icons.hd_rounded,
                label: VideoUiStrings.minQualityChip,
              ),
              _TipChip(
                icon: Icons.sd_storage_rounded,
                label: VideoUiStrings.maxFileSizeChip,
              ),
              _TipChip(
                icon: Icons.data_saver_on_rounded,
                label: VideoUiStrings.autoOptimizationChip,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TipChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Chip(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelPadding: const EdgeInsets.only(right: 8),
      // Correction: ne PAS mettre `const` ici car `icon` est une variable
      avatar: Icon(icon, size: 18, color: cs.primary),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: cs.primary,
        ),
      ),
      backgroundColor: cs.primary.withValues(alpha: .12),
    );
  }
}

/// Overlay de progression en “verre dépoli”
class _ProgressOverlay extends StatelessWidget {
  final UploadVideoController controller;
  final bool waiting; // état "chargement" avant d’ouvrir la galerie
  final bool preparing;

  const _ProgressOverlay({
    required this.controller,
    required this.waiting,
    required this.preparing,
  });

  @override
  Widget build(BuildContext context) {
    final uploading = controller.isUploading.value;
    final optimizing = controller.isOptimizing.value;
    final progress = controller.uploadProgress.value;
    final hasValue = progress > 0 && progress <= 1;
    final stage = controller.uploadStage.value;
    // Mirrors ProgressFullScreenLoader's canCancel: cancelUpload() is a
    // no-op while optimizing (server-side step), and there's nothing to
    // cancel during the plain gallery-picker `waiting` state.
    final canCancel = !waiting && !optimizing;

    String title;
    String subtitle = '';
    IconData icon;
    Widget progressWidget;

    if (waiting) {
      title = VideoUiStrings.overlayLoading;
      subtitle = VideoUiStrings.overlayWaiting;
      icon = Icons.hourglass_top_rounded;
      progressWidget = const CircularProgressIndicator(
        strokeWidth: 3,
        color: Colors.white,
      );
    } else if (preparing) {
      title = VideoUiStrings.uploadPreparationTitle;
      subtitle = VideoUiStrings.uploadPreparationSubtitle;
      icon = Icons.tune_rounded;
      progressWidget = const CircularProgressIndicator(
        strokeWidth: 3,
        color: Colors.white,
      );
    } else if (optimizing) {
      title = VideoUiStrings.uploadOptimizationTitle;
      subtitle = VideoUiStrings.uploadOptimizationSubtitle;
      icon = Icons.auto_awesome_rounded;
      progressWidget = const CircularProgressIndicator(
        strokeWidth: 3,
        color: Colors.white,
      );
    } else if (uploading) {
      title = VideoUiStrings.uploadProgressTitle;
      subtitle = stage.isNotEmpty
          ? stage
          : VideoUiStrings.uploadProgressSubtitle;
      icon = Icons.cloud_upload_rounded;
      progressWidget = CircularProgressIndicator(
        strokeWidth: 3,
        color: Colors.white,
        value: hasValue ? progress : null,
      );
    } else {
      title = VideoUiStrings.overlayWaiting;
      subtitle = VideoUiStrings.uploadProgressSubtitle;
      icon = Icons.sync_rounded;
      progressWidget = const CircularProgressIndicator(
        strokeWidth: 3,
        color: Colors.white,
      );
    }

    return PositionedFill(
      child: Container(
        alignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              width: 320,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: .08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(width: 58, height: 58, child: progressWidget),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AdColors.brand.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: Colors.white, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .9),
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                  if (uploading && hasValue) ...[
                    const SizedBox(height: 14),
                    Text(
                      '${(progress.clamp(0.0, 1.0) * 100).toInt()}%',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .95),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 6,
                      color: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: .25),
                    ),
                  ],
                  if (canCancel) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: controller.cancelUpload,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text(VideoUiStrings.uploadCancelAction),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Petit helper pour éviter le boilerplate Positioned.fill
class PositionedFill extends StatelessWidget {
  final Widget child;
  const PositionedFill({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(child: child);
  }
}
