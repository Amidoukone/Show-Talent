import 'package:flutter/material.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';

class TiktokVideoPlayer extends StatelessWidget {
  final CachedVideoPlayerPlusController? controller;
  final bool isPlaying;
  final bool hidePlayPauseIcon;
  final bool showControls;
  final bool showProgressBar;
  final bool isBuffering;
  final bool isLoading;
  final String? errorMessage;
  final String thumbnailUrl;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onRetry;

  const TiktokVideoPlayer({
    super.key,
    required this.controller,
    required this.isPlaying,
    required this.hidePlayPauseIcon,
    required this.showControls,
    required this.showProgressBar,
    required this.isBuffering,
    required this.isLoading,
    required this.errorMessage,
    required this.thumbnailUrl,
    this.onTogglePlayPause,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildContentState(),
        if (showControls && !hidePlayPauseIcon && controller?.value.isInitialized == true)
          _buildPlayPauseButton(),
        if (showProgressBar && controller?.value.isInitialized == true && !isBuffering && isPlaying)
          _buildProgressBar(),
      ],
    );
  }

  Widget _buildContentState() {
    if (errorMessage != null) return _buildError();

    final isReady = controller?.value.isInitialized == true;
    final showLoader = isLoading || isBuffering || !isReady;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildThumbnail(),
        if (isReady && !showLoader) _buildVideoPlayer(),
        if (showLoader) const Center(child: CircularProgressIndicator(color: Colors.white)),
      ],
    );
  }

  Widget _buildThumbnail() {
    return Image.network(
      thumbnailUrl,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image, size: 60, color: Colors.white),
      ),
    );
  }

  Widget _buildError() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildThumbnail(),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                errorMessage ?? 'Erreur de lecture vidéo',
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white10,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPlayer() {
    final value = controller?.value;
    if (value == null || value.hasError || !value.isInitialized || value.size.width <= 0 || value.size.height <= 0) {
      return _buildThumbnail();
    }

    return GestureDetector(
      onTap: showControls ? onTogglePlayPause : null,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: value.size.width,
          height: value.size.height,
          child: CachedVideoPlayerPlus(controller!),
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return Center(
      child: IconButton(
        iconSize: 64,
        icon: Icon(
          isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
          color: Colors.white.withOpacity(0.9),
        ),
        onPressed: onTogglePlayPause,
      ),
    );
  }

  Widget _buildProgressBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: VideoProgressIndicator(
        controller!,
        allowScrubbing: true,
        colors: const VideoProgressColors(
          playedColor: Colors.green,
          bufferedColor: Colors.white38,
          backgroundColor: Colors.white24,
        ),
        padding: const EdgeInsets.only(bottom: 4),
      ),
    );
  }
}
