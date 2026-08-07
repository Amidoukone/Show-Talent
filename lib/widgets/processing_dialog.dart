import 'package:flutter/material.dart';

import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/video_ui_strings.dart';

class ProcessingDialog extends StatefulWidget {
  final String message;
  final String? uploadStage;
  final double? progressPercent; // 0.0 to 1.0
  final VoidCallback? onCancel;

  const ProcessingDialog({
    super.key,
    this.message = VideoUiStrings.uploadOptimizationTitle,
    this.uploadStage,
    this.progressPercent,
    this.onCancel,
  });

  @override
  State<ProcessingDialog> createState() => _ProcessingDialogState();
}

class _ProcessingDialogState extends State<ProcessingDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<int> _dotAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();

    _dotAnimation = StepTween(begin: 1, end: 3).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String getDots(int count) => '.' * count;

  double? get _clampedProgress {
    final progress = widget.progressPercent;
    if (progress == null || !progress.isFinite) return null;
    return progress.clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AdSpacing.lg),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AdColors.surfaceCard,
                borderRadius: BorderRadius.circular(AdRadius.xl),
                border: Border.all(color: AdColors.divider),
                boxShadow: AdShadows.card(AdColors.black),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AdSpacing.xl),
                child: AnimatedBuilder(
                  animation: _dotAnimation,
                  builder: (context, child) {
                    final progress = _clampedProgress;

                    return Semantics(
                      namesRoute: true,
                      label: widget.message,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const SizedBox(
                                  width: 58,
                                  height: 58,
                                  child: CircularProgressIndicator(
                                    color: AdColors.brand,
                                    strokeWidth: 4,
                                  ),
                                ),
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color:
                                        AdColors.brand.withValues(alpha: .14),
                                    borderRadius:
                                        BorderRadius.circular(AdRadius.lg),
                                  ),
                                  child: const Icon(
                                    Icons.auto_awesome_rounded,
                                    color: AdColors.brand,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AdSpacing.lg),
                          Text(
                            '${widget.message}${getDots(_dotAnimation.value)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AdColors.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: AdSpacing.xs),
                          const Text(
                            VideoUiStrings.uploadOptimizationSubtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AdColors.onSurfaceMuted,
                              fontSize: 14,
                              height: 1.38,
                            ),
                          ),
                          if (widget.uploadStage != null) ...[
                            const SizedBox(height: AdSpacing.lg),
                            _ProcessingStagePill(label: widget.uploadStage!),
                          ],
                          if (progress != null) ...[
                            const SizedBox(height: AdSpacing.lg),
                            LinearProgressIndicator(
                              value: progress,
                              backgroundColor: AdColors.surfaceAlt,
                              color: AdColors.brand,
                              minHeight: 8,
                              borderRadius:
                                  BorderRadius.circular(AdRadius.pill),
                            ),
                            const SizedBox(height: AdSpacing.xs),
                            Text(
                              '${(progress * 100).toStringAsFixed(0)}%',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AdColors.onSurfaceMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          if (widget.onCancel != null) ...[
                            const SizedBox(height: AdSpacing.xl),
                            OutlinedButton.icon(
                              onPressed: widget.onCancel,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: AdColors.error,
                                side: BorderSide(
                                  color: AdColors.error.withValues(alpha: .45),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AdRadius.md),
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
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProcessingStagePill extends StatelessWidget {
  const _ProcessingStagePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AdColors.surfaceCardAlt,
        borderRadius: BorderRadius.circular(AdRadius.pill),
        border: Border.all(color: AdColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AdSpacing.md,
          vertical: AdSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.sync_rounded,
              color: AdColors.brand,
              size: 18,
            ),
            const SizedBox(width: AdSpacing.xs),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AdColors.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
