import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adfoot/services/app_logger.dart';

enum NetworkProfileTier { high, medium, low }

class NetworkProfile {
  const NetworkProfile({
    required this.tier,
    this.hasConnection = true,
    this.measuredKbps,
  });

  final NetworkProfileTier tier;
  final bool hasConnection;
  final double? measuredKbps;

  @override
  String toString() {
    final buffer = StringBuffer('NetworkProfile($tier');
    if (measuredKbps != null) {
      buffer.write(', ${measuredKbps!.toStringAsFixed(0)} kbps');
    }
    buffer.write(hasConnection ? ')' : ', offline)');
    return buffer.toString();
  }
}

class NetworkProfileService {
  NetworkProfileService({
    Connectivity? connectivity,
    http.Client? client,
    SharedPreferences? preferences,
    this.downloadUri =
        'https://speed.cloudflare.com/__down?bytes=$_throughputProbeBytes',
    this.probeUri = 'https://speed.cloudflare.com/__down?bytes=1',
    this.internalDownloadUri,
    this.internalProbeUri,
    this.externalProbesAllowed = true,
    this.softProbeFallback = false,
    this.measureTimeout = const Duration(seconds: 2),
    this.cacheTtl = const Duration(minutes: 10),
  })  : _connectivity = connectivity ?? Connectivity(),
        _client = client ?? http.Client(),
        _prefsFuture = preferences != null
            ? Future.value(preferences)
            : SharedPreferences.getInstance();

  final Connectivity _connectivity;
  final http.Client _client;
  final Future<SharedPreferences> _prefsFuture;

  final String downloadUri;
  final String probeUri;
  final String? internalDownloadUri;
  final String? internalProbeUri;
  final bool externalProbesAllowed;
  final bool softProbeFallback;
  final Duration measureTimeout;
  final Duration cacheTtl;

  static const _cacheKey = 'networkProfile:last';

  /// Bytes the throughput probe pulls.
  ///
  /// This used to be 8 000. Eight kilobytes over a connection the CDN probe
  /// has just warmed is not a throughput measurement: it is one round trip,
  /// and the number it produces says how far away Cloudflare is, not how fast
  /// the link runs. 256 KB takes long enough that the transfer, and not the
  /// setup, dominates the sample.
  ///
  /// The cost is the point of the trade: ~256 KB per detection, at most once
  /// per [cacheTtl] or per transport change, against video assets that
  /// adfoot-production serves at 5.2 to 9.7 Mb/s.
  static const int _throughputProbeBytes = 262144;

  /// The download probe gets its own, longer budget than the reachability
  /// HEAD: [measureTimeout] is about "is the CDN answering at all", and 2 s
  /// of it would put a 1 Mb/s floor under a measurement whose whole job is to
  /// recognise connections below that.
  static const Duration _throughputProbeTimeout = Duration(seconds: 4);

  /// Sentinel status used by the probe's own `onTimeout`.
  static const int _probeTimeoutStatus = 408;

  /* -------------------------------------------------------------------------- */
  /* Public API                                                                 */
  /* -------------------------------------------------------------------------- */

  Future<NetworkProfile> detectProfile() async {
    final connectivityResult = await _safeConnectivity();
    final transport = _transportLabel(connectivityResult);
    final now = DateTime.now();

    final cached = await _loadCachedProfile();
    final isCacheFresh = cached != null &&
        cached.profile.hasConnection &&
        now.difference(cached.timestamp) <= cacheTtl &&
        cached.transport == transport;

    final probeUriResolved = _resolveProbeUri();

    if (connectivityResult == ConnectivityResult.none &&
        probeUriResolved == null) {
      AppLogger.debug(
        '[NetworkProfile] Connectivity=none and probe disabled → offline',
      );

      final offline = NetworkProfile(
        tier: _baselineTier(connectivityResult),
        hasConnection: false,
      );

      await _saveCachedProfile(offline, transport, now);
      return offline;
    }

    if (probeUriResolved != null) {
      final cdnReachable = await _probeCdn(probeUriResolved);

      if (!cdnReachable && !softProbeFallback) {
        AppLogger.debug(
          '[NetworkProfile] CDN probe failed → offline (transport=$transport)',
        );

        final offline = NetworkProfile(
          tier: _baselineTier(connectivityResult),
          hasConnection: false,
        );

        await _saveCachedProfile(offline, transport, now);
        return offline;
      }

      if (!cdnReachable && softProbeFallback) {
        AppLogger.debug(
          '[NetworkProfile] CDN probe failed → soft fallback (transport=$transport)',
        );
      }
    } else {
      AppLogger.debug(
          '[NetworkProfile] Probe disabled by policy → soft fallback');
    }

    if (isCacheFresh) {
      AppLogger.debug(
        '[NetworkProfile] Using cached profile ${cached.profile} (transport=$transport)',
      );
      return cached.profile;
    }

    var tier = _baselineTier(connectivityResult);
    final throughput = await _measureThroughput();

    if (throughput != null) {
      tier = _tierFromThroughput(throughput);
      AppLogger.debug(
        '[NetworkProfile] Measured ${throughput.toStringAsFixed(0)} kbps → $tier',
      );
    } else {
      AppLogger.debug(
        '[NetworkProfile] Throughput probe failed, fallback tier $tier',
      );
    }

    final measured = NetworkProfile(
      tier: tier,
      hasConnection: true,
      measuredKbps: throughput,
    );

    await _saveCachedProfile(measured, transport, DateTime.now());
    return measured;
  }

  /* -------------------------------------------------------------------------- */
  /* Connectivity helpers                                                       */
  /* -------------------------------------------------------------------------- */

  Future<ConnectivityResult> _safeConnectivity() async {
    try {
      final dynamic res = await _connectivity.checkConnectivity();
      if (res is List<ConnectivityResult> && res.isNotEmpty) return res.first;
      if (res is ConnectivityResult) return res;
    } catch (_) {}
    return ConnectivityResult.none;
  }

  String _transportLabel(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.ethernet:
        return 'ethernet';
      case ConnectivityResult.wifi:
        return 'wifi';
      case ConnectivityResult.mobile:
        return 'mobile';
      case ConnectivityResult.satellite:
        return 'satellite';
      case ConnectivityResult.vpn:
        return 'vpn';
      case ConnectivityResult.bluetooth:
        return 'bluetooth';
      case ConnectivityResult.other:
        return 'other';
      case ConnectivityResult.none:
        return 'none';
    }
  }

  NetworkProfileTier _baselineTier(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.ethernet:
        return NetworkProfileTier.high;
      // Wi-Fi is a transport, not a speed. This baseline is only used when the
      // throughput probe fails -- exactly the situation where the connection
      // is least likely to sustain a 9 Mb/s asset -- and calling it `high`
      // there asks for the heaviest rendition on the flimsiest evidence
      // available. `medium` still plays; it just plays the lighter source.
      case ConnectivityResult.wifi:
      case ConnectivityResult.mobile:
      case ConnectivityResult.vpn:
        return NetworkProfileTier.medium;
      default:
        return NetworkProfileTier.low;
    }
  }

  /* -------------------------------------------------------------------------- */
  /* Probing / measurement                                                       */
  /* -------------------------------------------------------------------------- */

  Uri? _resolveProbeUri() {
    if (internalProbeUri != null && internalProbeUri!.isNotEmpty) {
      return Uri.parse(internalProbeUri!);
    }
    if (externalProbesAllowed) {
      return Uri.parse(probeUri);
    }
    return null;
  }

  Uri? _resolveDownloadUri() {
    if (internalDownloadUri != null && internalDownloadUri!.isNotEmpty) {
      return Uri.parse(internalDownloadUri!);
    }
    if (externalProbesAllowed) {
      return Uri.parse(downloadUri);
    }
    return null;
  }

  Future<bool> _probeCdn(Uri uri) async {
    try {
      final response = await _client.head(uri).timeout(
            measureTimeout,
            onTimeout: () =>
                http.Response.bytes([], _probeTimeoutStatus),
          );
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  /// Thresholds are a statement about what the *top rendition costs*, not
  /// about what feels fast.
  ///
  /// `high` is the only tier that asks for the heaviest source
  /// (`VideoSourceSelector._bestAtLeast(700)`); every other tier asks for
  /// `_bestAtMost(540)`. So "high" has to mean "can actually pull the biggest
  /// file we serve", and the biggest file we serve is no longer a 720p at
  /// ~2 Mb/s. adfoot-production on 2026-08-21 held 1080p passthrough assets at
  /// 5.17 and 9.66 Mb/s.
  ///
  /// At the old 1500 kbps a connection measuring 1.5 Mb/s was called `high`
  /// and handed a 9.66 Mb/s file — a six-fold mismatch. Every one of the eight
  /// playback sessions logged that day was tier `high`, and the 1080p ones
  /// came back at 103% rebuffer rate with 0% completion while the 720p ones
  /// sat at 0.04%. The tier was not describing the network, it was describing
  /// the era when the ceiling was 720p.
  ///
  /// Raising the bar was necessary but not sufficient: [_measureThroughput]
  /// was also handing this method bit/s while the thresholds were written in
  /// kbps, so *no* bar placed here could have discriminated anything. Both
  /// halves are fixed; the thresholds below only mean what they say now that
  /// the number arriving is genuinely kilobits per second.
  ///
  /// This is still a coarse proxy. The honest version compares the measured
  /// throughput against each source's own declared `bitrate`, which the
  /// backend now writes on every rendition — worth doing, but it changes the
  /// selector's signature and its pinned tests, so it is not a release-eve
  /// change.
  NetworkProfileTier _tierFromThroughput(double kbps) {
    if (kbps >= 6000) return NetworkProfileTier.high;
    if (kbps >= 2000) return NetworkProfileTier.medium;
    return NetworkProfileTier.low;
  }

  /// Measured throughput in **kilobits per second**, or `null` when the probe
  /// could not produce a number at all.
  ///
  /// Two things were wrong here, and together they made every device on every
  /// network report itself as [NetworkProfileTier.high].
  ///
  /// The first is arithmetic. `bits / milliseconds` *is* kbps — one bit per
  /// millisecond is one thousand bits per second is one kbit/s — so the
  /// trailing `* 1000` converted the result to bit/s and handed it to
  /// [_tierFromThroughput], whose thresholds are written in kbps. A phone
  /// measuring a genuine 213 kbps reported 213 333 and cleared the 6 000 bar
  /// a thousandfold. adfoot-production bears this out: over the fourteen days
  /// to 2026-08-22, **63 of 63** logged playback sessions carried
  /// `networkTier: "high"`, and the 1080p sessions among them came back at a
  /// 55% rebuffer rate against 4.7% for 720p.
  ///
  /// The second is the sample. 8 KB across a connection the reachability HEAD
  /// has already opened is one round trip; fixing only the unit would have
  /// swung every device to `low` for the opposite non-reason. See
  /// [_throughputProbeBytes].
  ///
  /// The result is deliberately conservative: connection setup is left inside
  /// the sample, so a link measuring 6 000 kbps here is running nearer 10 Mb/s
  /// in reality. That is the right bias — `high` is the only tier that asks
  /// for the heaviest rendition, and headroom over a 9.7 Mb/s asset is exactly
  /// what it should be claiming.
  Future<double?> _measureThroughput() async {
    try {
      final uri = _resolveDownloadUri();
      if (uri == null) {
        AppLogger.debug(
          '[NetworkProfile] Throughput probe disabled by policy → skip',
        );
        return null;
      }

      final stopwatch = Stopwatch()..start();
      final response = await _client.get(uri).timeout(
            _throughputProbeTimeout,
            onTimeout: () =>
                http.Response.bytes([], _probeTimeoutStatus),
          );
      stopwatch.stop();

      // A probe that ran out of budget is a measurement, not a failure: this
      // connection could not pull _throughputProbeBytes inside
      // _throughputProbeTimeout. Returning `null` for it sent precisely the
      // slowest links back to the optimistic transport baseline (`medium` on
      // Wi-Fi and mobile), which is the one place the baseline must not win.
      if (response.statusCode == _probeTimeoutStatus) {
        AppLogger.debug(
          '[NetworkProfile] Throughput probe timed out after '
          '${_throughputProbeTimeout.inSeconds}s → low',
        );
        return 0;
      }

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }

      final durationMs = max(stopwatch.elapsedMilliseconds, 1);
      return (response.bodyBytes.length * 8) / durationMs;
    } catch (_) {
      return null;
    }
  }

  /* -------------------------------------------------------------------------- */
  /* Cache (SharedPreferences)                                                   */
  /* -------------------------------------------------------------------------- */

  Future<_CachedProfile?> _loadCachedProfile() async {
    try {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;

      final map = jsonDecode(raw) as Map<String, dynamic>;

      final tier = NetworkProfileTier.values.firstWhere(
        (t) => t.name == map['tier'],
        orElse: () => NetworkProfileTier.low,
      );

      final profile = NetworkProfile(
        tier: tier,
        hasConnection: map['hasConnection'] == true,
        measuredKbps: (map['kbps'] as num?)?.toDouble(),
      );

      return _CachedProfile(
        profile: profile,
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int? ?? 0),
        transport: map['transport'] as String? ?? 'unknown',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedProfile(
    NetworkProfile profile,
    String transport,
    DateTime timestamp,
  ) async {
    try {
      final prefs = await _prefsFuture;
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'tier': profile.tier.name,
          'hasConnection': profile.hasConnection,
          'kbps': profile.measuredKbps,
          'ts': timestamp.millisecondsSinceEpoch,
          'transport': transport,
        }),
      );
    } catch (_) {}
  }
}

class _CachedProfile {
  const _CachedProfile({
    required this.profile,
    required this.timestamp,
    required this.transport,
  });

  final NetworkProfile profile;
  final DateTime timestamp;
  final String transport;
}
