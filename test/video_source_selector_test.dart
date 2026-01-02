import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/video_source_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fallbackMp4 = 'https://cdn.example.com/fallback.mp4';
  const lowMp4 = 'https://cdn.example.com/video_480.mp4';
  const highMp4 = 'https://cdn.example.com/video_720.mp4';
  const hlsUrl = 'https://cdn.example.com/playlist.m3u8';

  const sources = <VideoSource>[
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
    final url = VideoSourceSelector.chooseUrl(
      fallbackUrl: fallbackMp4,
      sources: sources,
      adaptiveEnabled: true,
      highBandwidth: true,
    );

    expect(url, highMp4);
  });

  test('returns fallback when adaptive flag is disabled', () {
    final url = VideoSourceSelector.chooseUrl(
      fallbackUrl: fallbackMp4,
      sources: sources,
      adaptiveEnabled: false,
      highBandwidth: true,
    );

    expect(url, fallbackMp4);
  });

  test('prefers HLS when enabled', () {
    final url = VideoSourceSelector.chooseUrl(
      fallbackUrl: fallbackMp4,
      sources: hlsSources,
      adaptiveEnabled: true,
      highBandwidth: true,
      preferHls: true,
    );

    expect(url, hlsUrl);
  });
}