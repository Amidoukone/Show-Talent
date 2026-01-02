import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FeatureFlagConfig {
  final bool adaptiveEnabled;
  final int rolloutPercent;
  final bool useHls;

  const FeatureFlagConfig({
    this.adaptiveEnabled = false,
    this.rolloutPercent = 0,
    this.useHls = false,
  });

  factory FeatureFlagConfig.fromData(Map<String, dynamic> data) {
    return FeatureFlagConfig(
      adaptiveEnabled: (data['adaptiveEnabled'] as bool?) ?? false,
      rolloutPercent: ((data['rolloutPercent'] as num?) ?? 0).clamp(0, 100).toInt(),
      useHls: (data['useHls'] as bool?) ?? false,
    );
  }
}

class FeatureFlagService {
  FeatureFlagService._internal();
  static final FeatureFlagService _instance = FeatureFlagService._internal();
  factory FeatureFlagService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  FeatureFlagConfig _cached = const FeatureFlagConfig();
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);

  FeatureFlagConfig get cached => _cached;

  Future<FeatureFlagConfig> fetchConfig() async {
    final now = DateTime.now();
    if (now.difference(_lastFetch) < const Duration(minutes: 5)) {
      return _cached;
    }

    try {
      final doc = await _firestore.collection('config').doc('streaming').get();
      final data = doc.data() ?? {};
      _cached = FeatureFlagConfig.fromData(data);
      _lastFetch = now;
    } catch (e) {
      debugPrint('❌ FeatureFlagService fetch error: $e');
    }

    return _cached;
  }

  bool isEnabledForUser(String? uid) {
    if (!_cached.adaptiveEnabled) return false;
    final percent = _cached.rolloutPercent.clamp(0, 100);
    if (percent >= 100) return true;
    final bucket = (uid ?? 'anonymous').hashCode.abs() % 100;
    return bucket < percent;
  }

  bool useHlsForUser(String? uid) {
    return isEnabledForUser(uid) && _cached.useHls;
  }
}