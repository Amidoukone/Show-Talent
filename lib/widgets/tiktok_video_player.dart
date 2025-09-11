import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class TiktokVideoPlayer extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool isPlaying;
  final bool hidePlayPauseIcon;
  final bool showControls;
  final bool showProgressBar;
  final bool isBuffering;
  final bool isLoading;
  final String? errorMessage;
  final String thumbnailUrl;
  final bool hasFirstFrame;
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
    required this.hasFirstFrame,
    this.onTogglePlayPause,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final value = controller?.value;
    final bool inited = value?.isInitialized ?? false;
    final bool hasErr = (value?.hasError ?? false) || (errorMessage != null);
    final bool showLoader = isLoading || isBuffering || !inited;

    return Semantics(
      label: 'Lecteur vidéo',
      liveRegion: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Couche contenu principal (vidéo/thumbnail/loader)
          _buildContentLayer(inited: inited, hasErr: hasErr, showLoader: showLoader),
          // Icône Play/Pause (optionnelle)
          if (_shouldShowPlayPause(inited)) _buildPlayPauseButton(),
          // Barre de progression (optionnelle)
          if (_shouldShowProgressBar(inited)) _buildProgressBar(),
        ],
      ),
    );
  }

  // ------ LAYERS ------

  Widget _buildContentLayer({
    required bool inited,
    required bool hasErr,
    required bool showLoader,
  }) {
    if (hasErr) return _buildError();

    return Stack(
      fit: StackFit.expand,
      children: [
        // Thumbnail visible tant qu'on n'a pas rendu la 1re frame
        _buildThumbnail(fadeOut: inited && hasFirstFrame),
        // Vidéo une fois initialisée
        if (inited) _buildVideoPlayer(),
        // Loader centré si nécessaire
        if (showLoader)
          const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            ),
          ),
      ],
    );
  }

  // ------ THUMBNAIL ------

  Widget _buildThumbnail({required bool fadeOut}) {
    return AnimatedOpacity(
      opacity: fadeOut ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.black),
        child: Image.network(
          thumbnailUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          loadingBuilder: (_, child, loadingProgress) =>
              loadingProgress == null
                  ? child
                  : const Center(child: CircularProgressIndicator(color: Colors.white)),
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image, size: 60, color: Colors.white),
          ),
        ),
      ),
    );
  }

  // ------ VIDEO ------

  Widget _buildVideoPlayer() {
    final value = controller!.value;

    // Sécurités : si l’état n’est pas bon, on laisse le thumbnail
    if (value.hasError || !value.isInitialized) {
      return _buildThumbnail(fadeOut: false);
    }

    // Rendu "cover" propre : on clippe pour éviter tout débordement
    return GestureDetector(
      onTap: showControls ? onTogglePlayPause : null,
      behavior: HitTestBehavior.opaque,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            // Valeurs fallback très sûres si le player n'a pas encore mesuré
            width: (value.size.width == 0) ? 9 : value.size.width,
            height: (value.size.height == 0) ? 16 : value.size.height,
            child: VideoPlayer(controller!),
          ),
        ),
      ),
    );
  }

  // ------ ERREUR ------

  Widget _buildError() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildThumbnail(fadeOut: false),
        Align(
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 44, color: Colors.redAccent),
                const SizedBox(height: 10),
                Text(
                  errorMessage ?? 'Erreur de lecture vidéo',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ------ UI OVERLAYS ------

  Widget _buildPlayPauseButton() {
    return IgnorePointer(
      ignoring: !showControls,
      child: Center(
        child: AnimatedOpacity(
          opacity: (showControls && !hidePlayPauseIcon) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 120),
          child: IconButton(
            iconSize: 64,
            icon: Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: Colors.white.withOpacity(0.9),
            ),
            onPressed: onTogglePlayPause,
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final ctrl = controller;
    if (ctrl == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !showControls, // scrubbing uniquement si contrôles visibles
        child: VideoProgressIndicator(
          ctrl,
          allowScrubbing: showControls,
          colors: const VideoProgressColors(
            playedColor: Colors.green,
            bufferedColor: Colors.white38,
            backgroundColor: Colors.white24,
          ),
          padding: const EdgeInsets.only(bottom: 4),
        ),
      ),
    );
  }

  // ------ CONDITIONS D’AFFICHAGE ------

  bool _shouldShowPlayPause(bool inited) {
    // Affiche l'icône si contrôles visibles + player initialisé
    return showControls && !hidePlayPauseIcon && inited;
  }

  bool _shouldShowProgressBar(bool inited) {
    // Barre uniquement si initialisé, en lecture et pas en buffering
    return showProgressBar && inited && isPlaying && !isBuffering;
  }
}
