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
  });

  final int maxActive;
  final int maxConcurrentInits;
  final int preloadRadius;
  final Duration preloadTimeout;
  final Duration activeTimeout;
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

  /// Waits at most [budget] for a fresh measurement.
  ///
  /// Used only where the answer changes which rendition is requested, and
  /// only when no measurement exists yet: playback must never block on the
  /// network profile.
  Future<void> awaitDetection(Duration budget) async {
    try {
      await _schedule().timeout(budget);
    } catch (_) {}
  }

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
      case NetworkProfileTier.high:
        return const VideoNetworkTuning(
          maxActive: 8,
          maxConcurrentInits: 3,
          preloadRadius: 3,
          preloadTimeout: Duration(seconds: 8),
          activeTimeout: Duration(seconds: 12),
        );
      case NetworkProfileTier.medium:
        return const VideoNetworkTuning(
          maxActive: 6,
          maxConcurrentInits: 2,
          preloadRadius: 2,
          preloadTimeout: Duration(seconds: 10),
          activeTimeout: Duration(seconds: 12),
        );
      case NetworkProfileTier.low:
        return const VideoNetworkTuning(
          maxActive: 4,
          maxConcurrentInits: 1,
          preloadRadius: 0,
          preloadTimeout: Duration(seconds: 12),
          activeTimeout: Duration(seconds: 15),
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
