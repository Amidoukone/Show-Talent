import 'package:adfoot/services/feature_flag_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote config is normalized to a single-rendition MP4 baseline', () {
    final config = FeatureFlagConfig.fromData({
      'adaptiveEnabled': true,
      'rolloutPercent': 100,
      'hlsPlaybackEnabled': true,
      'preferHlsPlayback': true,
      'useHls': true,
    });

    expect(config.isAdaptiveEnabledForUser('user-1'), isFalse);
    expect(config.isHlsPlaybackEnabledForUser('user-1'), isFalse);
    expect(config.shouldPreferHlsForUser('user-1'), isFalse);
  });

  test('direct configs can still express legacy adaptive values in tests', () {
    const config = FeatureFlagConfig(
      adaptiveEnabled: true,
      rolloutPercent: 100,
      hlsPlaybackEnabled: false,
      preferHlsPlayback: false,
    );

    expect(config.isAdaptiveEnabledForUser('user-1'), isTrue);
    expect(config.isHlsPlaybackEnabledForUser('user-1'), isFalse);
    expect(config.shouldPreferHlsForUser('user-1'), isFalse);
  });
}
