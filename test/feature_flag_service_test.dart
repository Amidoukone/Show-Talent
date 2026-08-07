import 'package:adfoot/services/feature_flag_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote config enables adaptive MP4 rollout only', () {
    final config = FeatureFlagConfig.fromData({
      'adaptiveEnabled': true,
      'rolloutPercent': 100,
      'alternatePlaybackEnabled': true,
    });

    expect(config.isAdaptiveEnabledForUser('user-1'), isTrue);
  });

  test('remote rollout percent is clamped', () {
    final disabled = FeatureFlagConfig.fromData({
      'adaptiveEnabled': true,
      'rolloutPercent': -10,
    });
    final capped = FeatureFlagConfig.fromData({
      'adaptiveEnabled': true,
      'rolloutPercent': 150,
    });

    expect(disabled.isAdaptiveEnabledForUser('user-1'), isFalse);
    expect(capped.isAdaptiveEnabledForUser('user-1'), isTrue);
  });

  test('direct configs can still express adaptive MP4 rollout in tests', () {
    const config = FeatureFlagConfig(
      adaptiveEnabled: true,
      rolloutPercent: 100,
    );

    expect(config.isAdaptiveEnabledForUser('user-1'), isTrue);
  });
}
