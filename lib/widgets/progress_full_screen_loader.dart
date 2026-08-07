import 'package:adfoot/controller/upload_video_controller.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProgressFullScreenLoader extends StatelessWidget {
  const ProgressFullScreenLoader({
    super.key,
    required this.uploadController,
  });

  final UploadVideoController uploadController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.72),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxCardWidth =
                constraints.maxWidth > 460 ? 420.0 : constraints.maxWidth - 40;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AdSpacing.lg,
                  vertical: AdSpacing.xl,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxCardWidth),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AdColors.surfaceCard,
                      borderRadius: BorderRadius.circular(AdRadius.xl),
                      border: Border.all(color: AdColors.divider),
                      boxShadow: AdShadows.card(AdColors.black),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AdSpacing.xl),
                      child: Obx(() {
                        final state = _presentationState();

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AdColors.brand.withValues(alpha: .14),
                                  borderRadius:
                                      BorderRadius.circular(AdRadius.lg),
                                ),
                                child: Icon(
                                  state.isOptimizing
                                      ? Icons.auto_awesome_rounded
                                      : Icons.cloud_upload_rounded,
                                  color: AdColors.brand,
                                  size: 30,
                                ),
                              ),
                            ),
                            const SizedBox(height: AdSpacing.lg),
                            Text(
                              state.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AdColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: AdSpacing.xs),
                            Text(
                              state.subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.38,
                                color: AdColors.onSurfaceMuted,
                              ),
                            ),
                            const SizedBox(height: AdSpacing.xl),
                            _UploadCurrentStageCard(state: state),
                            const SizedBox(height: AdSpacing.lg),
                            if (state.isOptimizing)
                              const LinearProgressIndicator(
                                backgroundColor: AdColors.surfaceAlt,
                                color: AdColors.brand,
                                minHeight: 8,
                              )
                            else ...[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    VideoUiStrings.uploadProgressLabel,
                                    style: TextStyle(
                                      color: AdColors.onSurfaceMuted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${(state.progress * 100).toInt()}%',
                                    style: const TextStyle(
                                      color: AdColors.onSurface,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AdSpacing.xs),
                              LinearProgressIndicator(
                                value: state.progress,
                                backgroundColor: AdColors.surfaceAlt,
                                color: AdColors.brand,
                                minHeight: 8,
                                borderRadius:
                                    BorderRadius.circular(AdRadius.pill),
                              ),
                            ],
                            const SizedBox(height: AdSpacing.xl),
                            _UploadStageTimeline(activeStep: state.activeStep),
                            if (state.canCancel) ...[
                              const SizedBox(height: AdSpacing.xl),
                              OutlinedButton.icon(
                                onPressed: uploadController.cancelUpload,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  foregroundColor: AdColors.error,
                                  side: BorderSide(
                                    color:
                                        AdColors.error.withValues(alpha: .45),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(AdRadius.md),
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                icon: const Icon(Icons.close_rounded, size: 20),
                                label: const Text(
                                  VideoUiStrings.uploadCancelAction,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  _UploadProgressPresentation _presentationState() {
    final rawProgress = uploadController.uploadProgress.value;
    final progress =
        rawProgress.isFinite ? rawProgress.clamp(0.0, 1.0).toDouble() : 0.0;
    final stage = uploadController.uploadStage.value;
    final isPreparing = uploadController.isPreparing.value;
    final isOptimizing = uploadController.isOptimizing.value;
    final displayedStage = _displayedStage(
      stage: stage,
      progress: progress,
      isOptimizing: isOptimizing,
    );

    final title = isOptimizing
        ? VideoUiStrings.uploadOptimizationTitle
        : isPreparing
            ? VideoUiStrings.uploadPreparationTitle
            : VideoUiStrings.uploadProgressTitle;
    final subtitle = isOptimizing
        ? VideoUiStrings.uploadOptimizationSubtitle
        : isPreparing
            ? VideoUiStrings.uploadPreparationSubtitle
            : VideoUiStrings.uploadProgressSubtitle;

    return _UploadProgressPresentation(
      title: title,
      subtitle: subtitle,
      currentStage: displayedStage,
      progress: progress,
      activeStep: _activeStep(
        progress: progress,
        isPreparing: isPreparing,
        isOptimizing: isOptimizing,
      ),
      isOptimizing: isOptimizing,
      canCancel: !isOptimizing,
    );
  }

  String _displayedStage({
    required String stage,
    required double progress,
    required bool isOptimizing,
  }) {
    if (isOptimizing) return VideoUiStrings.uploadStageOptimize;
    if (stage.isNotEmpty) return stage;
    if (progress < 0.05) return VideoUiStrings.uploadStagePreparing;
    if (progress < 0.25) return VideoUiStrings.uploadStageCompressing;
    if (progress < 0.65) return VideoUiStrings.uploadStageUploadingVideo;
    if (progress < 1.0) {
      return VideoUiStrings.uploadStageUploadingThumbnail;
    }
    return VideoUiStrings.uploadStageFinalize;
  }

  int _activeStep({
    required double progress,
    required bool isPreparing,
    required bool isOptimizing,
  }) {
    if (isOptimizing || progress >= 0.95) return 3;
    if (isPreparing || progress < 0.18) return 0;
    if (progress < 0.70) return 1;
    if (progress < 0.95) return 2;
    return 3;
  }
}

class _UploadProgressPresentation {
  const _UploadProgressPresentation({
    required this.title,
    required this.subtitle,
    required this.currentStage,
    required this.progress,
    required this.activeStep,
    required this.isOptimizing,
    required this.canCancel,
  });

  final String title;
  final String subtitle;
  final String currentStage;
  final double progress;
  final int activeStep;
  final bool isOptimizing;
  final bool canCancel;
}

class _UploadCurrentStageCard extends StatelessWidget {
  const _UploadCurrentStageCard({required this.state});

  final _UploadProgressPresentation state;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AdColors.surfaceCardAlt,
        borderRadius: BorderRadius.circular(AdRadius.lg),
        border: Border.all(color: AdColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AdSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: state.isOptimizing
                  ? const CircularProgressIndicator(
                      color: AdColors.brand,
                      strokeWidth: 3,
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: AdColors.brand.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(AdRadius.pill),
                      ),
                      child: const Icon(
                        Icons.sync_rounded,
                        color: AdColors.brand,
                        size: 18,
                      ),
                    ),
            ),
            const SizedBox(width: AdSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    VideoUiStrings.uploadCurrentStepLabel,
                    style: TextStyle(
                      color: AdColors.onSurfaceMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.currentStage,
                    style: const TextStyle(
                      color: AdColors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadStageTimeline extends StatelessWidget {
  const _UploadStageTimeline({required this.activeStep});

  final int activeStep;

  static const List<String> _labels = [
    VideoUiStrings.uploadStepPrepare,
    VideoUiStrings.uploadStepTransfer,
    VideoUiStrings.uploadStepThumbnail,
    VideoUiStrings.uploadStepFinalize,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(_labels.length, (index) {
        return _UploadStageStep(
          index: index,
          label: _labels[index],
          activeStep: activeStep,
          isLast: index == _labels.length - 1,
        );
      }),
    );
  }
}

class _UploadStageStep extends StatelessWidget {
  const _UploadStageStep({
    required this.index,
    required this.label,
    required this.activeStep,
    required this.isLast,
  });

  final int index;
  final String label;
  final int activeStep;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isCompleted = index < activeStep;
    final isActive = index == activeStep;
    final color =
        isCompleted || isActive ? AdColors.brand : AdColors.onSurfaceDisabled;

    return Semantics(
      label: label,
      selected: isActive,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              AnimatedContainer(
                duration: AdMotion.fast,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AdColors.brand
                      : color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(AdRadius.pill),
                  border: Border.all(color: color.withValues(alpha: .5)),
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_rounded
                      : isActive
                          ? Icons.more_horiz_rounded
                          : Icons.circle_rounded,
                  color: isCompleted ? AdColors.brandOn : color,
                  size: isActive ? 18 : 12,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 24,
                  color: isCompleted ? AdColors.brand : AdColors.divider,
                ),
            ],
          ),
          const SizedBox(width: AdSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: TextStyle(
                  color:
                      isActive ? AdColors.onSurface : AdColors.onSurfaceMuted,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
