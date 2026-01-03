import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum NetworkProfileTier { high, medium, low }

class NetworkProfile {
  const NetworkProfile({
    required this.tier,
    this.hasConnection = true,
    this.measuredKbps,
    this.preferHls = false,
  });

  final NetworkProfileTier tier;
  final bool hasConnection;
  final double? measuredKbps;
  final bool preferHls;

  @override
  String toString() {
    final buffer = StringBuffer('NetworkProfile($tier');
    if (measuredKbps != null) {
      buffer.write(', ${measuredKbps!.toStringAsFixed(0)} kbps');
    }
    if (preferHls) buffer.write(', preferHls');
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
        'https://speed.cloudflare.com/__down?bytes=8000', // ~8KB probe
    this.probeUri = 'https://speed.cloudflare.com/__down?bytes=1',
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
  final Duration measureTimeout;
  final Duration cacheTtl;

  static const _cacheKey = 'networkProfile:last';

  /* -------------------------------------------------------------------------- */
  /* Public API                                                                */
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

    // CDN probe = vérité terrain (plus fiable que Connectivity seul)
    final cdnReachable = await _probeCdn();
    if (!cdnReachable) {
      debugPrint(
        '[NetworkProfile] CDN probe failed → offline (transport=$transport)',
      );

      final offline = NetworkProfile(
        tier: _baselineTier(connectivityResult),
        hasConnection: false,
        preferHls: false,
      );

      await _saveCachedProfile(offline, transport, now);
      return offline;
    }

    if (isCacheFresh) {
      debugPrint(
        '[NetworkProfile] Using cached profile ${cached.profile} (transport=$transport)',
      );
      return cached.profile;
    }

    final preferHls =
        connectivityResult == ConnectivityResult.wifi ||
        connectivityResult == ConnectivityResult.ethernet;

    var tier = _baselineTier(connectivityResult);
    final throughput = await _measureThroughput();

    if (throughput != null) {
      tier = _tierFromThroughput(throughput);
      debugPrint(
        '[NetworkProfile] Measured ${throughput.toStringAsFixed(0)} kbps → $tier',
      );
    } else {
      debugPrint(
        '[NetworkProfile] Throughput probe failed, fallback tier $tier',
      );
    }

    final measured = NetworkProfile(
      tier: tier,
      hasConnection: true,
      measuredKbps: throughput,
      preferHls: preferHls,
    );

    await _saveCachedProfile(measured, transport, DateTime.now());
    return measured;
  }

  /* -------------------------------------------------------------------------- */
  /* Connectivity helpers                                                      */
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
      case ConnectivityResult.wifi:
        return NetworkProfileTier.high;
      case ConnectivityResult.mobile:
      case ConnectivityResult.vpn:
        return NetworkProfileTier.medium;
      default:
        return NetworkProfileTier.low;
    }
  }

  /* -------------------------------------------------------------------------- */
  /* Probing / measurement                                                      */
  /* -------------------------------------------------------------------------- */

  Future<bool> _probeCdn() async {
    try {
      final response = await _client
          .head(Uri.parse(probeUri))
          .timeout(
            measureTimeout,
            onTimeout: () => http.Response.bytes([], 408),
          );
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  NetworkProfileTier _tierFromThroughput(double kbps) {
    if (kbps >= 1500) return NetworkProfileTier.high;
    if (kbps >= 700) return NetworkProfileTier.medium;
    return NetworkProfileTier.low;
  }

  Future<double?> _measureThroughput() async {
    try {
      final stopwatch = Stopwatch()..start();
      final response = await _client
          .get(Uri.parse(downloadUri))
          .timeout(
            measureTimeout,
            onTimeout: () => http.Response.bytes([], 408),
          );

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }

      stopwatch.stop();
      final durationMs = max(stopwatch.elapsedMilliseconds, 1);
      final kbps = (response.bodyBytes.length * 8) / durationMs;
      return kbps * 1000; // kb/s
    } catch (_) {
      return null;
    }
  }

  /* -------------------------------------------------------------------------- */
  /* Cache (SharedPreferences)                                                  */
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
        preferHls: map['preferHls'] == true,
      );

      return _CachedProfile(
        profile: profile,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['ts'] as int? ?? 0),
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
          'preferHls': profile.preferHls,
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
