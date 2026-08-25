/// Which URLs an *active* initialisation currently owns, per context.
///
/// `VideoManager.initializeController` has two kinds of caller and one queue.
/// A preload waits for an init slot; the video on screen never does, because
/// [VideoNetworkTuning.maxConcurrentInits] exists to keep *background* work
/// off the connection and the video the user is looking at is not background
/// work.
///
/// The two meet at step (2) of the pipeline: a request for the video now on
/// screen finds an in-flight future for the same URL and awaits it, which is
/// correct — two inits for one URL is the leak that once left a native player
/// reachable from no map at all, holding a MediaCodec instance for the rest
/// of the session. What it inherits along with that future is the preload's
/// place in the queue, and that queue allows a 20 s wait for a stalled
/// connection to give a slot back.
///
/// So "the video on screen never queues" held only when the video on screen
/// had not been preloaded first — the one case the preload exists to make
/// fast, and the shape adfoot-production logged on 2026-08-23 at 17:21:
/// `loadState: "loading"` for 25 s with no init error, because nothing had
/// failed. It had not started.
///
/// A claim is what the suspended preload polls for. It is taken before the
/// active request can await anything and released whichever way that request
/// ends: a claim that outlived its request would let every later preload of
/// that URL skip the queue for the rest of the session, which is the same
/// bug with the sign flipped.
class ActiveInitRegistry {
  final Map<String, Set<String>> _claimsByContext = {};

  /// Records that an active request owns [url] in [contextKey].
  void claim(String contextKey, String url) {
    _claimsByContext.putIfAbsent(contextKey, () => <String>{}).add(url);
  }

  /// Whether the video on screen is waiting on [url] in [contextKey].
  bool isClaimed(String contextKey, String url) =>
      _claimsByContext[contextKey]?.contains(url) ?? false;

  /// Releases the claim taken by [claim].
  void release(String contextKey, String url) {
    final claims = _claimsByContext[contextKey];
    if (claims == null) return;
    claims.remove(url);
    if (claims.isEmpty) _claimsByContext.remove(contextKey);
  }

  /// Forgets everything held for a context that is going away.
  void forgetContext(String contextKey) {
    _claimsByContext.remove(contextKey);
  }
}
