import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FeatureFlagConfig {
  final bool adaptiveEnabled;
  final int rolloutPercent;
  final bool hlsPlaybackEnabled;
  final bool preferHlsPlayback;

  const FeatureFlagConfig({
    this.adaptiveEnabled = false,
    this.rolloutPercent = 0,
    this.hlsPlaybackEnabled = false,
    this.preferHlsPlayback = false,
  });

  factory FeatureFlagConfig.fromData(Map<String, dynamic> data) {
    return FeatureFlagConfig(
      // Single-rendition MP4 baseline: adaptive and HLS flags remain readable
      // in Firestore for backward compatibility, but they no longer drive
      // runtime playback in the mobile app.
      adaptiveEnabled: false,
      rolloutPercent: 0,
      hlsPlaybackEnabled: false,
      preferHlsPlayback: false,
    );
  }

  bool isAdaptiveEnabledForUser(String? uid) {
    if (!adaptiveEnabled) {
      return false;
    }
    return _isUserInRollout(uid, rolloutPercent);
  }

  bool isHlsPlaybackEnabledForUser(String? uid) {
    if (!hlsPlaybackEnabled) {
      return false;
    }
    return _isUserInRollout(uid, rolloutPercent);
  }

  bool shouldPreferHlsForUser(String? uid) {
    return isHlsPlaybackEnabledForUser(uid) && preferHlsPlayback;
  }

  bool _isUserInRollout(String? uid, int percent) {
    final safePercent = percent.clamp(0, 100);
    if (safePercent <= 0) {
      return false;
    }
    if (safePercent >= 100) {
      return true;
    }
    final bucket = (uid ?? 'anonymous').hashCode.abs() % 100;
    return bucket < safePercent;
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
      debugPrint('FeatureFlagService fetch error: $e');
    }

    return _cached;
  }

  bool isEnabledForUser(String? uid) {
    return _cached.isAdaptiveEnabledForUser(uid);
  }

  bool isAdaptiveEnabledForUser(String? uid) {
    return _cached.isAdaptiveEnabledForUser(uid);
  }

  bool isHlsPlaybackEnabledForUser(String? uid) {
    return _cached.isHlsPlaybackEnabledForUser(uid);
  }

  bool shouldPreferHlsForUser(String? uid) {
    return _cached.shouldPreferHlsForUser(uid);
  }

  bool useHlsForUser(String? uid) {
    return shouldPreferHlsForUser(uid);
  }
}
