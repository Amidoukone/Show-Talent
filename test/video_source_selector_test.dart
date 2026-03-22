import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/video_source_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fallbackMp4 = 'https://cdn.example.com/fallback.mp4';
  const lowestMp4 = 'https://cdn.example.com/video_360.mp4';
  const lowMp4 = 'https://cdn.example.com/video_480.mp4';
  const highMp4 = 'https://cdn.example.com/video_720.mp4';
  const hlsUrl = 'https://cdn.example.com/playlist.m3u8';

  const sources = <VideoSource>[
    VideoSource(url: lowestMp4, quality: '360p', type: 'mp4', height: 360),
    VideoSource(url: highMp4, quality: '720p', type: 'mp4', height: 720),
    VideoSource(url: lowMp4, quality: '480p', type: 'mp4', height: 480),
  ];

  const hlsSources = <VideoSource>[
    VideoSource(url: hlsUrl, quality: '720p', type: 'hls', height: 720),
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
      'prioritized sources collapse to the canonical mp4 when adaptive is disabled',
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

  test('keeps MP4 first even when HLS preference is requested', () {
    final url = VideoSourceSelector.chooseUrl(
      fallbackUrl: fallbackMp4,
      sources: hlsSources,
      adaptiveEnabled: true,
      highBandwidth: true,
      preferHls: true,
    );

    expect(url, highMp4);
  });

  test('does not select HLS when preferHls is disabled', () {
    final url = VideoSourceSelector.chooseUrl(
      fallbackUrl: fallbackMp4,
      sources: hlsSources,
      adaptiveEnabled: true,
      highBandwidth: true,
      preferHls: false,
    );

    expect(url, highMp4);
  });

  test('prioritized sources keep MP4 first when preferHls is disabled', () {
    final ordered = VideoSourceSelector.prioritizedSources(
      fallbackUrl: fallbackMp4,
      sources: hlsSources,
      adaptiveEnabled: true,
      highBandwidth: true,
      preferHls: false,
    );

    expect(ordered.first.url, highMp4);
    expect(ordered.any((source) => source.url == hlsUrl), isFalse);
  });

  test('falls back to legacy HLS only when no MP4 source exists', () {
    final url = VideoSourceSelector.chooseUrl(
      fallbackUrl: '',
      sources: const [
        VideoSource(url: hlsUrl, quality: '720p', type: 'hls', height: 720),
      ],
      adaptiveEnabled: true,
      highBandwidth: true,
      preferHls: true,
    );

    expect(url, hlsUrl);
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
