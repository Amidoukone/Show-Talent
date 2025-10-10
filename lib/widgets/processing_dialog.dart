import 'package:flutter/material.dart';

class ProcessingDialog extends StatefulWidget {
  final String message;
  final String? uploadStage;
  final double? progressPercent; // 0.0 → 1.0
  final VoidCallback? onCancel;

  const ProcessingDialog({
    super.key,
    this.message = "Optimisation en cours",
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

  // Sécurise la valeur du pourcentage pour l’affichage (0..1)
  double? get _clampedProgress =>
      widget.progressPercent?.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          width: 300,
          decoration: BoxDecoration(
            // Remplacement withOpacity → withValues(alpha: ...)
            color: Colors.black.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: AnimatedBuilder(
            animation: _dotAnimation,
            builder: (context, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 12),
                  Text(
                    "${widget.message}${getDots(_dotAnimation.value)}",
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.uploadStage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.uploadStage!,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_clampedProgress != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      "${(_clampedProgress! * 100).toStringAsFixed(0)}%",
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                  if (widget.onCancel != null) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text(
                        "Annuler",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ]
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
