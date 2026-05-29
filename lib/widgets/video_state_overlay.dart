import 'package:flutter/material.dart';

import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/utils/video_ui_strings.dart';

enum VideoStateOverlayMode { loading, error }

class VideoStateOverlay extends StatelessWidget {
  const VideoStateOverlay.loading({
    super.key,
    this.message = loadingMessage,
    this.onRetry,
    this.showRetry = false,
  }) : mode = VideoStateOverlayMode.loading;

  const VideoStateOverlay.error({
    super.key,
    String? message,
    this.onRetry,
  })  : mode = VideoStateOverlayMode.error,
        message = message ?? errorMessage,
        showRetry = true;

  static const String loadingMessage = VideoUiStrings.loadingMessage;
  static const String slowLoadingMessage = VideoUiStrings.slowLoadingMessage;
  static const String errorMessage = VideoUiStrings.playbackUnavailable;
  static const String retryLabel = VideoUiStrings.retry;

  final VideoStateOverlayMode mode;
  final String message;
  final VoidCallback? onRetry;
  final bool showRetry;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case VideoStateOverlayMode.loading:
        return _buildLoading();
      case VideoStateOverlayMode.error:
        return _buildError();
    }
  }

  Widget _buildLoading() {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: AdColors.brand,
                  strokeWidth: 2.4,
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  message.trim().isEmpty ? loadingMessage : message.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (showRetry && onRetry != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text(retryLabel),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final resolvedMessage =
        message.trim().isEmpty ? errorMessage : message.trim();

    return Container(
      color: Colors.black.withValues(alpha: 0.48),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_disabled_rounded,
            size: 46,
            color: AdColors.brand,
          ),
          const SizedBox(height: 12),
          Text(
            resolvedMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(retryLabel),
              style: FilledButton.styleFrom(
                backgroundColor: AdColors.brand,
                foregroundColor: AdColors.brandOn,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
