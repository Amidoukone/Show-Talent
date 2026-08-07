import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/services/app_logger.dart';

class FeatureFlagConfig {
  final bool adaptiveEnabled;
  final int rolloutPercent;

  const FeatureFlagConfig({
    this.adaptiveEnabled = false,
    this.rolloutPercent = 0,
  });

  factory FeatureFlagConfig.fromData(Map<String, dynamic> data) {
    final rawPercent = data['rolloutPercent'];
    return FeatureFlagConfig(
      adaptiveEnabled: data['adaptiveEnabled'] == true,
      rolloutPercent:
          rawPercent is num ? rawPercent.round().clamp(0, 100).toInt() : 0,
    );
  }

  bool isAdaptiveEnabledForUser(String? uid) {
    if (!adaptiveEnabled) {
      return false;
    }
    return _isUserInRollout(uid, rolloutPercent);
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
      AppLogger.debug('FeatureFlagService fetch error: $e');
    }

    return _cached;
  }

  bool isEnabledForUser(String? uid) {
    return _cached.isAdaptiveEnabledForUser(uid);
  }

  bool isAdaptiveEnabledForUser(String? uid) {
    return _cached.isAdaptiveEnabledForUser(uid);
  }
}
