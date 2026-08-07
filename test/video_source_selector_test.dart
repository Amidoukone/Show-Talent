import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/video_source_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fallbackMp4 = 'https://cdn.example.com/fallback.mp4';
  const lowestMp4 = 'https://cdn.example.com/video_360.mp4';
  const lowMp4 = 'https://cdn.example.com/video_480.mp4';
  const highMp4 = 'https://cdn.example.com/video_720.mp4';
  const nonMp4Url = 'https://cdn.example.com/video.webm';

  const sources = <VideoSource>[
    VideoSource(url: lowestMp4, quality: '360p', type: 'mp4', height: 360),
    VideoSource(url: highMp4, quality: '720p', type: 'mp4', height: 720),
    VideoSource(url: lowMp4, quality: '480p', type: 'mp4', height: 480),
  ];

  const mixedSources = <VideoSource>[
    VideoSource(url: nonMp4Url, quality: '720p', type: 'webm', height: 720),
    ...sources,
  ];

  test('selects 480p source on low bandwidth', () {
    final url = VideoSourceSelector.chooseUrl(
      fallbackUrl: fallbackMp4,
      sources: sources,
      adaptiveEnabled: true,
      highBandwidth: false,
    );

    expect(url, lowMp4);
  });

  test('selects 720p source on high bandwidth', () {
    final preferred = VideoSourceSelector.preferredSource(
      fallbackUrl: fallbackMp4,
      sources: sources,
      adaptiveEnabled: true,
      highBandwidth: true,
    );

    expect(preferred?.url, highMp4);
    expect(preferred?.height, 720);
  });

  test('returns the highest MP4 source when adaptive flag is disabled', () {
    final url = VideoSourceSelector.chooseUrl(
      fallbackUrl: fallbackMp4,
      sources: sources,
      adaptiveEnabled: false,
      highBandwidth: true,
    );

    expect(url, highMp4);
  });

  test(
      'prioritized sources collapse to the canonical MP4 when adaptive is disabled',
      () {
    final ordered = VideoSourceSelector.prioritizedSources(
      fallbackUrl: fallbackMp4,
      sources: sources,
      adaptiveEnabled: false,
      highBandwidth: true,
    );

    expect(ordered.map((source) => source.url).toList(), [highMp4]);
  });

  test('keeps the matched fallback source when canonical URL is present', () {
    final url = VideoSourceSelector.chooseUrl(
      fallbackUrl: lowMp4,
      sources: sources,
      adaptiveEnabled: false,
      highBandwidth: true,
    );

    expect(url, lowMp4);
  });

  test('ignores non-MP4 sources when selecting playback candidates', () {
    final ordered = VideoSourceSelector.prioritizedSources(
      fallbackUrl: fallbackMp4,
      sources: mixedSources,
      adaptiveEnabled: true,
      highBandwidth: true,
    );

    expect(ordered.first.url, highMp4);
    expect(ordered.any((source) => source.url == nonMp4Url), isFalse);
  });

  test('does not use a non-MP4 fallback URL', () {
    final ordered = VideoSourceSelector.prioritizedSources(
      fallbackUrl: nonMp4Url,
      sources: const [],
      adaptiveEnabled: true,
      highBandwidth: true,
    );

    expect(ordered, isEmpty);
    expect(
      VideoSourceSelector.chooseUrl(
        fallbackUrl: nonMp4Url,
        sources: const [],
        adaptiveEnabled: true,
        highBandwidth: true,
      ),
      isEmpty,
    );
  });

  test('source lookup ignores non-MP4 urls', () {
    final source = VideoSourceSelector.sourceForUrl(
      url: nonMp4Url,
      sources: mixedSources,
    );

    expect(source, isNull);
  });

  test('prioritized sources keep 480p ahead of 360p on low bandwidth', () {
    final ordered = VideoSourceSelector.prioritizedSources(
      fallbackUrl: fallbackMp4,
      sources: sources,
      adaptiveEnabled: true,
      highBandwidth: false,
    );

    expect(
      ordered.take(3).map((source) => source.url).toList(),
      [lowMp4, lowestMp4, highMp4],
    );
  });
}
