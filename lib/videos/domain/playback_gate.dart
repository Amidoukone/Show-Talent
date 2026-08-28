/// Who is allowed to *start* a video, and when.
///
/// Every widget in the playback path already asked this question correctly:
/// `SmartVideoPlayer._isActuallyVisible` checks that the app is resumed, that
/// the route is current and that the index matches, before it plays anything.
/// The manager asked it nowhere — and the manager is what actually calls
/// `play()`. `initializeController(autoPlay: true)` does it in three places,
/// from inside an await that can outlive the reason it was started.
///
/// Two production symptoms came from that single gap:
///
///  * A video kept playing after the app was sent to the background. The
///    widget went passive and paused what it held, but an initialisation
///    already in flight completed a moment later and started the sound again
///    with no screen to show it. The widget had done its job; it simply was
///    not the last one to speak.
///
///  * A video left while it was still loading began playing once it finished,
///    from wherever the user had scrolled to. `VideoFocusOrchestrator` is
///    careful here — it re-checks its request token before calling `play()`
///    itself — but it passes `autoPlay: true`, so the manager had already
///    started playback inside the awaited call, before that check could run.
///    The guard existed; it arrived too late.
///
/// This is deliberately only about *starting*. Nothing here stops a video the
/// user is watching, and a request that fails the gate is simply not played:
/// the widget layer starts it when it becomes visible again.
class PlaybackGate {
  /// The video each context is focused on, keyed by its original URL.
  ///
  /// Fed from `VideoManager.pauseAllExcept`, whose two callers — the focus
  /// orchestrator on every index change, and `SmartVideoPlayer` when it takes
  /// the screen — both pass the URL that is meant to keep playing. That makes
  /// it the one place which already knows the answer, so no second mechanism
  /// had to be invented to track focus.
  ///
  /// Original URLs rather than resolved ones on purpose: a resolved key can
  /// change under an adaptive rendition switch between the moment focus is
  /// recorded and the moment an initialisation completes, and a mismatch
  /// there would silently refuse to play the *right* video.
  final Map<String, String> _focusedUrlByContext = <String, String>{};

  bool _resumed = true;

  /// Whether the app is in the foreground, as far as playback is concerned.
  bool get isAppResumed => _resumed;

  /// Records the app leaving or returning to the foreground.
  ///
  /// Returns true when this actually changed something, so the caller knows
  /// whether it still has to pause what is playing.
  bool setAppResumed(bool resumed) {
    if (_resumed == resumed) return false;
    _resumed = resumed;
    return true;
  }

  /// Records which video owns [contextKey]'s screen, or none.
  void setFocus(String contextKey, String? url) {
    if (url == null) {
      _focusedUrlByContext.remove(contextKey);
      return;
    }
    _focusedUrlByContext[contextKey] = url;
  }

  /// The video [contextKey] is currently focused on, if it has one.
  String? focusedUrl(String contextKey) => _focusedUrlByContext[contextKey];

  /// Whether playback of [url] in [contextKey] may start right now.
  ///
  /// False while the app is backgrounded, and false when [url] is not the
  /// video this context is focused on. A context that has never recorded a
  /// focus says yes: that is the first activation of a freshly opened feed,
  /// which must not be blocked by the absence of a previous page.
  bool canStart(String contextKey, String url) {
    if (!_resumed) return false;
    final focused = _focusedUrlByContext[contextKey];
    if (focused == null) return true;
    return focused == url;
  }

  /// Forgets a context's focus. Its next activation is a first one again.
  void forgetContext(String contextKey) {
    _focusedUrlByContext.remove(contextKey);
  }

  void reset() {
    _focusedUrlByContext.clear();
    _resumed = true;
  }
}
