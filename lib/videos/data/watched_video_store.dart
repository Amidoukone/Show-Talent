import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adfoot/services/app_logger.dart';

/// What counts as having watched a video.
///
/// Deliberately not "it was on screen": a feed being scrolled through puts
/// every video on screen for a moment, and treating that as watched would
/// empty the unseen set in one fast scroll — which is exactly the state the
/// ordering exists to avoid.
///
/// Either threshold is enough, because clips here run from 9 s to 160 s
/// (adfoot-production, 2026-08-24) and neither rule alone covers both ends:
/// three seconds is meaningless for a 160 s clip, half a clip is unreachable
/// for a 160 s one in normal browsing.
class WatchedVideoPolicy {
  const WatchedVideoPolicy._();

  static const Duration minWatchTime = Duration(seconds: 3);
  static const double minCompletion = 0.5;

  static bool countsAsWatched({
    required bool hadFirstFrame,
    required Duration? maxPosition,
    required double completionRate,
  }) {
    // Nothing was rendered, so nothing was seen — whatever the clock says.
    if (!hadFirstFrame) return false;

    if (completionRate >= minCompletion) return true;

    final watched = maxPosition ?? Duration.zero;
    return watched >= minWatchTime;
  }
}

/// Which videos this device has already watched, and when.
///
/// Local by design. The feed's job is to show a recruiter every player it can
/// without repeating itself, and answering "have I seen this one?" needs no
/// server, no document per user and no behavioural profile — three costs that
/// would buy nothing at this catalogue size. Nothing here leaves the phone.
///
/// Keyed by video id and capped at [maxEntries], oldest watch evicted first:
/// the store is an ordering hint, not an archive, and a hint that grows
/// without bound is a bug waiting for a large account.
class WatchedVideoStore {
  WatchedVideoStore._();

  static final WatchedVideoStore instance = WatchedVideoStore._();

  static const String storageKey = 'video.watched.v1';
  static const int maxEntries = 400;

  final Map<String, int> _watchedAtMsById = <String, int>{};
  Future<void>? _loading;
  bool _loaded = false;

  /// Overridable clock and storage, so the ordering can be exercised without
  /// a platform channel.
  DateTime Function() _now = DateTime.now;
  Future<SharedPreferences> Function() _preferences =
      SharedPreferences.getInstance;

  bool get isLoaded => _loaded;

  @visibleForTesting
  int get entryCount => _watchedAtMsById.length;

  /// Reads the store once. Safe to call from anywhere, any number of times.
  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await _preferences();
      final raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final id = key.toString();
            final at = value is num ? value.toInt() : int.tryParse('$value');
            if (id.isNotEmpty && at != null) {
              _watchedAtMsById[id] = at;
            }
          });
        }
      }
    } catch (error) {
      // A corrupt or unreadable store must never keep the feed from opening:
      // the worst case is an unordered feed, which is what shipped before.
      AppLogger.debug('[WatchedVideoStore] load failed, starting empty: $error');
      _watchedAtMsById.clear();
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  bool hasWatched(String videoId) => _watchedAtMsById.containsKey(videoId);

  /// When [videoId] was last watched, or null if it never was.
  int? watchedAtMs(String videoId) => _watchedAtMsById[videoId];

  /// Records a watch, in memory immediately and on disk when it can.
  ///
  /// The in-memory write lands first on purpose: the ordering is read from
  /// memory, and a feed refreshed before the disk write completed must still
  /// see the video the user just watched.
  Future<void> markWatched(String videoId) async {
    if (videoId.isEmpty) return;

    await ensureLoaded();
    _watchedAtMsById[videoId] = _now().millisecondsSinceEpoch;
    _evictOldest();

    try {
      final prefs = await _preferences();
      await prefs.setString(storageKey, jsonEncode(_watchedAtMsById));
    } catch (error) {
      AppLogger.debug('[WatchedVideoStore] persist failed for $videoId: $error');
    }
  }

  void _evictOldest() {
    if (_watchedAtMsById.length <= maxEntries) return;

    final byOldestFirst = _watchedAtMsById.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final excess = _watchedAtMsById.length - maxEntries;
    for (var i = 0; i < excess; i++) {
      _watchedAtMsById.remove(byOldestFirst[i].key);
    }
  }

  @visibleForTesting
  void resetForTests({
    Map<String, int>? watchedAtMsById,
    DateTime Function()? now,
    Future<SharedPreferences> Function()? preferences,
  }) {
    _watchedAtMsById
      ..clear()
      ..addAll(watchedAtMsById ?? const <String, int>{});
    _now = now ?? DateTime.now;
    _preferences = preferences ?? SharedPreferences.getInstance;
    _loading = null;
    _loaded = true;
  }
}
