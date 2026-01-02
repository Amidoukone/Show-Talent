import 'dart:async';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
    if (measuredKbps != null) buffer.write(', ${measuredKbps!.toStringAsFixed(0)} kbps');
    buffer.write(hasConnection ? ')' : ', offline)');
    return buffer.toString();
  }
}

class NetworkProfileService {
  NetworkProfileService({
    Connectivity? connectivity,
    http.Client? client,
    this.downloadUri =
        'https://speed.cloudflare.com/__down?bytes=40000', // ~40KB quick probe
    this.measureTimeout = const Duration(seconds: 2),
  })  : _connectivity = connectivity ?? Connectivity(),
        _client = client ?? http.Client();

  final Connectivity _connectivity;
  final http.Client _client;
  final String downloadUri;
  final Duration measureTimeout;

  Future<NetworkProfile> detectProfile() async {
    final connectivityResult = await _safeConnectivity();
    final hasConnection = connectivityResult != ConnectivityResult.none;
    var tier = _baselineTier(connectivityResult);

    if (!hasConnection) return NetworkProfile(tier: NetworkProfileTier.low, hasConnection: false);

    final throughput = await _measureThroughput();
    if (throughput != null) {
      tier = _tierFromThroughput(throughput);
      debugPrint('[NetworkProfile] Measured throughput ${throughput.toStringAsFixed(0)} kbps => $tier');
    } else {
      debugPrint('[NetworkProfile] Throughput probe skipped/failing, fallback tier $tier');
    }

    return NetworkProfile(tier: tier, hasConnection: hasConnection, measuredKbps: throughput);
  }

  Future<ConnectivityResult> _safeConnectivity() async {
    try {
      final dynamic res = await _connectivity.checkConnectivity();
      if (res is List<ConnectivityResult> && res.isNotEmpty) return res.first;
      if (res is ConnectivityResult) return res;
    } catch (_) {}
    return ConnectivityResult.none;
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

  NetworkProfileTier _tierFromThroughput(double kbps) {
    if (kbps >= 1500) return NetworkProfileTier.high; // ~1.5 Mbps and above
    if (kbps >= 700) return NetworkProfileTier.medium;
    return NetworkProfileTier.low;
  }

  Future<double?> _measureThroughput() async {
    try {
      final stopwatch = Stopwatch()..start();
      final response = await _client
          .get(Uri.parse(downloadUri))
          .timeout(measureTimeout, onTimeout: () => http.Response.bytes([], 408));

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      stopwatch.stop();

      final durationMs = max(stopwatch.elapsedMilliseconds, 1);
      final kbps = (response.bodyBytes.length * 8) / durationMs; // kilobits per millisecond
      return kbps * 1000; // -> kilobits per second
    } catch (_) {
      return null;
    }
  }
}