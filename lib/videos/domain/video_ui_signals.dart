import 'package:flutter/foundation.dart';

/// Where a video is between "asked for" and "playable".
enum VideoLoadState { loading, ready, errorTimeout, errorSource }

class _WatchEntry {
  _WatchEntry() : notifier = ValueNotifier<int>(0);

  final ValueNotifier<int> notifier;
  int watcherCount = 0;
}

/// What the UI is allowed to know about a video, and how it is told.
///
/// Three things travel together and were scattered through `VideoManager`:
/// the load state of each video, the rendition finally chosen for it, and the
/// notifiers the widgets rebuild on.
///
/// They are one concern because they change together and must be forgotten
/// together — the bug this shape prevents is a widget still rendering the
/// state of a context that has been torn down.
class VideoUiSignals {
  /// Bumped on every change, for listeners that do not care which video moved.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<String, Map<String, VideoLoadState>> _loadStatesByContext = {};

  /// originalUrl -> resolvedUrl (the rendition actually being played).
  final Map<String, Map<String, String>> _resolvedUrlByContext = {};

  /// Per-video notifiers, owned by the widgets through [watch] / [unwatch].
  final Map<String, Map<String, _WatchEntry>> _watchersByContext = {};

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  VideoLoadState? loadState(String contextKey, String url) =>
      _loadStatesByContext[contextKey]?[url];

  String? resolvedUrl(String contextKey, String originalUrl) =>
      _resolvedUrlByContext[contextKey]?[originalUrl];

  /// The resolved URL for [originalUrl], or [originalUrl] itself.
  ///
  /// The cache and the LRU are keyed by the *resolved* URL, so almost every
  /// lookup in `VideoManager` goes through this.
  String resolveKey(String contextKey, String originalUrl) =>
      _resolvedUrlByContext[contextKey]?[originalUrl] ?? originalUrl;

  /// Every original URL that resolved to [resolved] in this context.
  List<String> originalUrlsFor(String contextKey, String resolved) {
    final mapping = _resolvedUrlByContext[contextKey];
    if (mapping == null) return const [];
    return mapping.entries
        .where((entry) => entry.value == resolved)
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  /// The original URLs of this context whose resolved form is in [resolvedUrls].
  List<String> originalUrlsAmong(
    String contextKey,
    Set<String> resolvedUrls,
  ) {
    final mapping = _resolvedUrlByContext[contextKey];
    if (mapping == null || resolvedUrls.isEmpty) return const [];
    return mapping.entries
        .where((entry) => resolvedUrls.contains(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------------

  void setLoadState(String contextKey, String url, VideoLoadState state) {
    _loadStatesByContext.putIfAbsent(contextKey, () => {})[url] = state;
    _notify(contextKey: contextKey, url: url);
  }

  void setResolvedUrl(
    String contextKey,
    String originalUrl,
    String resolved,
  ) {
    _resolvedUrlByContext.putIfAbsent(contextKey, () => {})[originalUrl] =
        resolved;
    _notify(contextKey: contextKey, url: originalUrl);
  }

  /// Makes sure this context has somewhere to record resolved URLs.
  void ensureContext(String contextKey) {
    _resolvedUrlByContext.putIfAbsent(contextKey, () => {});
  }

  /// Forgets one video, and tells whoever was watching it.
  void forget(String contextKey, String url) {
    _loadStatesByContext[contextKey]?.remove(url);
    _resolvedUrlByContext[contextKey]?.remove(url);
    _notify(contextKey: contextKey, url: url);
  }

  /// Forgets a whole context, and wakes every widget still watching it.
  ///
  /// Dropping the states without waking the watchers left a widget listening
  /// to its own per-URL notifier rendering the state it had *before* the
  /// teardown, until something else happened to rebuild it. The entries
  /// themselves stay: they are owned by [watch] / [unwatch], that is by the
  /// widgets' own lifecycle, not by the context.
  void forgetContext(String contextKey) {
    _loadStatesByContext.remove(contextKey);
    _resolvedUrlByContext.remove(contextKey);
    _notify();

    final byUrl = _watchersByContext[contextKey];
    if (byUrl == null) return;
    for (final entry in byUrl.values) {
      _bump(entry.notifier);
    }
  }

  // ---------------------------------------------------------------------------
  // Watching
  // ---------------------------------------------------------------------------

  ValueListenable<int> watch(String contextKey, String url) {
    final byUrl = _watchersByContext.putIfAbsent(contextKey, () => {});
    final entry = byUrl.putIfAbsent(url, _WatchEntry.new);
    entry.watcherCount++;
    return entry.notifier;
  }

  void unwatch(String contextKey, String url) {
    final byUrl = _watchersByContext[contextKey];
    final entry = byUrl?[url];
    if (entry == null) return;

    entry.watcherCount--;
    if (entry.watcherCount > 0) return;

    entry.notifier.dispose();
    byUrl?.remove(url);
    if (byUrl != null && byUrl.isEmpty) {
      _watchersByContext.remove(contextKey);
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _notify({String? contextKey, String? url}) {
    _bump(revision);

    if (contextKey == null || url == null) return;

    final entry = _watchersByContext[contextKey]?[url];
    if (entry == null) return;

    _bump(entry.notifier);
  }

  /// Wraps around rather than growing without bound: this is a change
  /// counter, and nothing reads it as a quantity.
  void _bump(ValueNotifier<int> notifier) {
    final next = notifier.value + 1;
    notifier.value = next > 1000000 ? 0 : next;
  }

  /// Zeroes every counter.
  ///
  /// Not `@visibleForTesting`: `VideoManager.resetNetworkProfileStateForTests`
  /// is the actual seam and forwards here, so marking this would flag
  /// production code that exists for the test.
  void resetCounters() {
    revision.value = 0;
    for (final byUrl in _watchersByContext.values) {
      for (final entry in byUrl.values) {
        entry.notifier.value = 0;
      }
    }
  }
}
