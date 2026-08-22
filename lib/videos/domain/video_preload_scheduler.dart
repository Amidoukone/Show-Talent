import 'dart:async';

import 'package:adfoot/models/video.dart';
import 'package:adfoot/services/app_logger.dart';

/// Starts one neighbour's preload. Supplied by `VideoManager`.
typedef PreloadVideo =
    Future<void> Function(String contextKey, Video video, {String? activeUrl});

/// Decides which neighbours to warm, in what order, and how far apart.
///
/// Two separate concerns live here, and both were tuned against real
/// behaviour rather than guessed:
///
/// * **Order** follows the direction of travel. Somebody scrolling down wants
///   the video below first; somebody scrolling back up wants the one above.
/// * **Spacing** keeps the second and later neighbours off the connection for
///   a moment. Firing every neighbour at once put the video the user is
///   watching in competition with all of them simultaneously.
///
/// A per-context request token discards the neighbours of a page the user has
/// already left: without it, a fast scroll left a trail of downloads for
/// videos nobody was going to reach.
class VideoPreloadScheduler {
  VideoPreloadScheduler({required this.preload});

  final PreloadVideo preload;

  static const Duration _secondaryPreloadDelay = Duration(milliseconds: 220);
  static const Duration _maxPreloadStaggerDelay = Duration(milliseconds: 700);

  final Map<String, int> _requestTokensByContext = {};

  /// Warms the neighbours of [index] within [radius].
  void scheduleAround({
    required String contextKey,
    required List<Video> videos,
    required int index,
    required int radius,
    String? activeUrl,
    bool preferForward = true,
  }) {
    if (radius <= 0) return;

    final token = (_requestTokensByContext[contextKey] ?? 0) + 1;
    _requestTokensByContext[contextKey] = token;

    final seenUrls = <String>{};
    final active = activeUrl?.trim();
    var position = 0;

    for (final candidateIndex in orderAround(
      totalVideos: videos.length,
      index: index,
      radius: radius,
      preferForward: preferForward,
    )) {
      final video = videos[candidateIndex];
      final candidateUrl = video.videoUrl.trim();
      if (candidateUrl.isEmpty || candidateUrl == active) continue;
      if (!seenUrls.add(candidateUrl)) continue;

      unawaited(
        _preloadAfterDelay(
          contextKey: contextKey,
          video: video,
          requestToken: token,
          delay: delayForPosition(position),
          activeUrl: activeUrl,
        ),
      );
      position++;
    }
  }

  /// Invalidates whatever this context had in flight.
  void forgetContext(String contextKey) {
    _requestTokensByContext.remove(contextKey);
  }

  Future<void> _preloadAfterDelay({
    required String contextKey,
    required Video video,
    required int requestToken,
    required Duration delay,
    String? activeUrl,
  }) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }

    // The user has moved on; these neighbours are no longer anybody's.
    if (_requestTokensByContext[contextKey] != requestToken) return;

    try {
      await preload(contextKey, video, activeUrl: activeUrl);
    } catch (error) {
      AppLogger.debug(
        '[VideoPreloadScheduler] Preload skipped for ${video.videoUrl}: $error',
      );
    }
  }

  /// How long the neighbour at [position] waits before it starts.
  ///
  /// The first is immediate — it is the one the user is most likely to reach.
  Duration delayForPosition(int position) {
    if (position <= 0) return Duration.zero;
    final delayMs = _secondaryPreloadDelay.inMilliseconds * position;
    final cappedMs = delayMs > _maxPreloadStaggerDelay.inMilliseconds
        ? _maxPreloadStaggerDelay.inMilliseconds
        : delayMs;
    return Duration(milliseconds: cappedMs);
  }

  /// Neighbour indices, nearest first, in the direction of travel.
  List<int> orderAround({
    required int totalVideos,
    required int index,
    required int radius,
    bool preferForward = true,
  }) {
    if (totalVideos <= 0 || radius <= 0) return const [];
    if (index < 0 || index >= totalVideos) return const [];

    final ordered = <int>[];
    for (int distance = 1; distance <= radius; distance++) {
      final previousIndex = index - distance;
      final nextIndex = index + distance;

      if (preferForward) {
        if (nextIndex < totalVideos) ordered.add(nextIndex);
        if (previousIndex >= 0) ordered.add(previousIndex);
      } else {
        if (previousIndex >= 0) ordered.add(previousIndex);
        if (nextIndex < totalVideos) ordered.add(nextIndex);
      }
    }

    return ordered;
  }
}
