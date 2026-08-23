import 'package:cached_video_player_plus/cached_video_player_plus.dart';

/// Which native players have been released.
///
/// `dispose()` does not flip `isInitialized` or `hasError` — a released
/// `CachedVideoPlayerPlus` is indistinguishable from a live one by looking at
/// it. `VideoManager.attempt()` has always known this and re-checks before
/// handing a controller back from its LRU, but every *other* holder of a
/// reference was left to find out on its own, and none of them could.
///
/// That matters because a controller is released from six places inside
/// `VideoManager` — `_enforceLimit`, `_enforceGlobalLimit`, `disposeUrls`,
/// `releaseControllersExcept`, `disposeAllForContext` and the failure paths of
/// `attempt()` — and none of them tells the widget still holding it. The
/// widget then calls `play()` or `pause()` on a native player id that no
/// longer exists. Nothing in Dart throws; the failure is on the other side of
/// the platform channel.
///
/// adfoot-production on 2026-08-23 shows the shape of it: the app died during
/// playback on the first launch of 1.0.7+24 and Crashlytics reported 100%
/// crash-free sessions for that release, because no Dart or Java exception was
/// ever raised.
///
/// The pressure went up, not down, when the app-wide decoder budget dropped
/// from 8 to 4: eviction is now the normal case rather than the rare one.
///
/// An [Expando] keys on identity and holds no strong reference, so a released
/// player is still collected normally.
class PlayerLifetimeRegistry {
  final Expando<bool> _released = Expando<bool>('videoPlayerReleased');

  /// Records that [player] has been disposed and must not be used again.
  void markReleased(CachedVideoPlayerPlus player) {
    _released[player] = true;
  }

  /// Whether [player] is still ours to call into.
  bool isLive(CachedVideoPlayerPlus? player) {
    if (player == null) return false;
    return _released[player] != true;
  }
}
