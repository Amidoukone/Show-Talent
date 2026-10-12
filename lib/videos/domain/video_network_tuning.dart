import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:adfoot/controller/connectivity_controller.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:adfoot/videos/domain/network_profile.dart';

/// What a network tier costs the playback machinery.
class VideoNetworkTuning {
  const VideoNetworkTuning({
    required this.maxActive,
    required this.maxConcurrentInits,
    required this.preloadRadius,
    required this.preloadTimeout,
    required this.activeTimeout,
    required this.firstFrameTimeout,
    required this.bufferingStrikesBeforeReload,
    required this.thumbnailPrefetchRadius,
  });

  final int maxActive;
  final int maxConcurrentInits;
  final int preloadRadius;
  final Duration preloadTimeout;
  final Duration activeTimeout;

  /// How long a player may hold a picture back before playback is rebuilt.
  ///
  /// Counted from the moment `play()` is called -- so after a successful
  /// `initialize()` -- and it is the deadline for the first rendered frame,
  /// not for the init. The two are different waits: init ends when the header
  /// and enough samples to decode have arrived, the first frame ends when the
  /// decoder has actually produced one, and on a weak link the second can
  /// legitimately take several seconds more.
  ///
  /// This was the last fixed threshold in the playback pipeline: a flat 6 s
  /// on every tier, while `activeTimeout` next to it already stretched to
  /// 15 s for the slowest. A `low` connection would therefore finish a 15 s
  /// init, start buffering, get torn down at 6 s by
  /// `SmartVideoPlayer._startFirstFrameWatchdog`, and start over from an
  /// empty buffer -- three times, because that is the automatic recovery
  /// budget, after which the user is shown "la lecture a échoué" for a video
  /// that was downloading perfectly well, just slowly. Every recovery threw
  /// away the bytes that had already arrived, so the slower the link, the
  /// more certain the failure.
  final Duration firstFrameTimeout;

  /// Watchdog ticks of pre-first-frame buffering tolerated before a rebuild.
  ///
  /// Sampled every `SmartVideoPlayer._stallCheckInterval` (700 ms), and only
  /// counted before the first frame -- buffering during playback is handled
  /// by the stall strikes instead. Fixed at 8 (~5.6 s) for the same reason
  /// and with the same consequence as [firstFrameTimeout]: it is a budget for
  /// how long the network may take, so it belongs to the network tier.
  final int bufferingStrikesBeforeReload;

  /// How many neighbours' thumbnails are warmed either side of the visible
  /// video.
  ///
  /// Everything else in this table exists because the connection is finite,
  /// and thumbnails were the one request this reasoning had not reached.
  /// `VideoFeedPager` warms them on every page change, *before* calling
  /// `onIndexChanged` -- so on a slow link a handful of image downloads were
  /// issued ahead of the video the user is waiting for, on the very tier
  /// where [preloadRadius] drops to 0 because the pipeline decided this link
  /// must not compete with itself.
  ///
  /// Never 0, unlike [preloadRadius]. The thumbnail is what stands in for the
  /// picture while a slow stream fills its buffer: on this tier it is worth
  /// more, not less. One neighbour instead of two keeps the next swipe
  /// covered at a fifth of the requests.
  final int thumbnailPrefetchRadius;
}

/// Detects the connection's tier and turns it into playback settings.
///
/// Detection and tuning were spread across `VideoManager` next to the
/// controller cache and the init pipeline, which meant the one question this
/// answers — "how hard may we push this connection?" — had no single place to
/// read.
///
/// The tier is not cosmetic: it decides which rendition is asked for, how many
/// neighbours are warmed, and how many native players stay alive. Until the
/// throughput arithmetic was fixed it answered `high` for every device on
/// every network, and adfoot-production's 1080p sessions came back at a 55%
/// rebuffer rate.
class VideoNetworkTuningController {
  VideoNetworkTuningController() {
    _apply(bootstrapProfile, reason: 'bootstrap', markInitialized: false);
    _listenForConnectivityChanges();
  }

  /// What playback assumes before the first measurement lands.
  ///
  /// Deliberately `medium`, never `high`: the first videos of a session would
  /// otherwise be requested at the heaviest rendition on no evidence at all.
  static const NetworkProfile bootstrapProfile = NetworkProfile(
    tier: NetworkProfileTier.medium,
    hasConnection: true,
  );

  NetworkProfileService _service = NetworkProfileService();

  final ValueNotifier<NetworkProfile?> profileNotifier =
      ValueNotifier<NetworkProfile?>(null);

  NetworkProfile? _profile;
  Future<NetworkProfile>? _inFlight;
  int _requestToken = 0;
  bool _initialized = false;

  VideoNetworkTuning _tuning = _tuningFor(NetworkProfileTier.medium);

  NetworkProfile? get profile => _profile;
  VideoNetworkTuning get tuning => _tuning;

  /// True once a real measurement has replaced [bootstrapProfile].
  bool get isInitialized => _initialized;

  bool get isHighBandwidth => _profile?.tier == NetworkProfileTier.high;

  // ---------------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------------

  /// NetworkProfileService caches the detected tier for up to 10 minutes (or
  /// until the OS-reported transport changes), so a Wi-Fi connection that
  /// quietly degrades without switching transport can keep serving a stale
  /// "high tier" classification. A connectivity transition is a reasonable
  /// moment to force a fresh detection rather than wait out the TTL.
  ///
  /// ConnectivityService is a permanent app-wide singleton and so is the
  /// video manager that owns this, so the subscription is meant to live for
  /// the whole process — intentionally never stored or cancelled.
  void _listenForConnectivityChanges() {
    try {
      ConnectivityService().connectionStream.listen(
        (_) => unawaited(refresh()),
        onError: (_) {},
      );
    } catch (_) {
      // connectivity_plus can fail to initialize on some devices; detection
      // still works via its own TTL-based refresh.
    }
  }

  void override(NetworkProfile profile) {
    _requestToken++;
    _inFlight = null;
    _apply(profile, reason: 'override');
  }

  Future<void> warm() async {
    try {
      await _schedule();
    } catch (_) {}
  }

  Future<void> refresh() async {
    try {
      await _schedule(force: true);
    } catch (_) {}
  }

  /// Starts a detection without waiting for it.
  void ensureWarm() => unawaited(_schedule());

  Future<NetworkProfile> _schedule({bool force = false}) {
    if (!force && _inFlight != null) {
      return _inFlight!;
    }

    final requestToken = ++_requestToken;
    final future = _service.detectProfile();
    _inFlight = future;

    future
        .then((profile) {
          if (!identical(_inFlight, future) || _requestToken != requestToken) {
            return;
          }
          _inFlight = null;
          _apply(profile, reason: 'detected');
        })
        .catchError((error, stackTrace) {
          if (!identical(_inFlight, future) || _requestToken != requestToken) {
            return;
          }
          _inFlight = null;
          AppLogger.debug('[VideoNetworkTuning] Refresh failed: $error');
        });

    return future;
  }

  void _apply(
    NetworkProfile profile, {
    String reason = 'manual',
    bool markInitialized = true,
  }) {
    _profile = profile;
    _initialized = markInitialized;
    profileNotifier.value = profile;
    _tuning = _tuningFor(profile.tier);

    AppLogger.debug(
      '[VideoNetworkTuning] Applied ($reason): $profile -> '
      'radius=${_tuning.preloadRadius} maxActive=${_tuning.maxActive} '
      'concurrent=${_tuning.maxConcurrentInits}',
    );
  }

  static VideoNetworkTuning _tuningFor(NetworkProfileTier tier) {
    switch (tier) {
      // maxActive counts *players*, and a player is a hardware decoder.
      // Since a preload past the nearest neighbour now warms the file without
      // opening one, these numbers no longer have to cover the whole preload
      // radius -- the radius costs downloads, this costs decoders.
      case NetworkProfileTier.high:
        return const VideoNetworkTuning(
          maxActive: 4,
          maxConcurrentInits: 3,
          preloadRadius: 3,
          preloadTimeout: Duration(seconds: 8),
          activeTimeout: Duration(seconds: 12),
          firstFrameTimeout: Duration(seconds: 6),
          bufferingStrikesBeforeReload: 8,
          thumbnailPrefetchRadius: 2,
        );
      case NetworkProfileTier.medium:
        return const VideoNetworkTuning(
          maxActive: 3,
          maxConcurrentInits: 2,
          preloadRadius: 2,
          preloadTimeout: Duration(seconds: 10),
          activeTimeout: Duration(seconds: 12),
          firstFrameTimeout: Duration(seconds: 9),
          bufferingStrikesBeforeReload: 12,
          thumbnailPrefetchRadius: 2,
        );
      case NetworkProfileTier.low:
        return const VideoNetworkTuning(
          maxActive: 2,
          maxConcurrentInits: 1,
          preloadRadius: 0,
          preloadTimeout: Duration(seconds: 12),
          activeTimeout: Duration(seconds: 15),
          // Patient on purpose, and never patient forever: nothing here waits
          // past the automatic recovery budget without the user seeing the
          // "Connexion lente" overlay, which offers a manual retry of its own
          // after a few seconds. The choice is between waiting for a slow
          // download and destroying it; waiting is the one that can succeed.
          firstFrameTimeout: Duration(seconds: 16),
          bufferingStrikesBeforeReload: 22,
          thumbnailPrefetchRadius: 1,
        );
    }
  }

  /// Replaces the detector and returns to a known profile.
  ///
  /// Not `@visibleForTesting`: `VideoManager` exposes the seam and forwards.
  void resetForTests({
    NetworkProfileService? service,
    NetworkProfile profile = bootstrapProfile,
  }) {
    _service = service ?? NetworkProfileService();
    _inFlight = null;
    _requestToken = 0;
    _apply(profile, reason: 'test-reset');
  }
}
