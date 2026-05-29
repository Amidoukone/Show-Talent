import 'package:adfoot/models/video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses playback contract and ignores non-MP4 sources', () {
    final video = Video.fromMap({
      'id': 'video-1',
      'videoUrl': 'https://cdn.example.com/video.mp4',
      'thumbnail': 'https://cdn.example.com/thumb.jpg',
      'playback': {
        'version': 1,
        'mode': 'mp4_only',
        'sourceAsset': {
          'url': 'https://cdn.example.com/video.mp4',
          'path': 'videos/video-1.mp4',
          'type': 'mp4',
          'quality': '480p',
          'height': 480,
        },
        'fallback': {
          'url': 'https://cdn.example.com/video.mp4',
          'path': 'videos/video-1.mp4',
          'type': 'mp4',
          'quality': '480p',
          'height': 480,
        },
      },
      'sources': [
        {
          'url': 'https://cdn.example.com/video.webm',
          'type': 'webm',
          'quality': '720p',
          'height': 720,
        },
      ],
    });

    expect(video.videoUrl, 'https://cdn.example.com/video.mp4');
    expect(video.playback?.mode, 'mp4_only');
    expect(video.playback?.sourceAsset?.path, 'videos/video-1.mp4');
    expect(video.sources.map((source) => source.url), [
      'https://cdn.example.com/video.mp4',
    ]);
  });

  test('parses versioned MP4 ladder contracts without losing fallback root',
      () {
    final video = Video.fromMap({
      'id': 'video-3',
      'videoUrl': 'https://cdn.example.com/video-3.mp4',
      'playback': {
        'version': 2,
        'mode': 'multi_rendition_mp4',
        'sources': [
          {
            'url': 'https://cdn.example.com/mp4/video-3/360p.mp4',
            'path': 'mp4/video-3/360p.mp4',
            'type': 'mp4',
            'quality': '360p',
            'height': 360,
            'bitrate': 450000,
          },
          {
            'url': 'https://cdn.example.com/mp4/video-3/480p.mp4',
            'path': 'mp4/video-3/480p.mp4',
            'type': 'mp4',
            'quality': '480p',
            'height': 480,
            'bitrate': 900000,
          },
          {
            'url': 'https://cdn.example.com/mp4/video-3/720p.mp4',
            'path': 'mp4/video-3/720p.mp4',
            'type': 'mp4',
            'quality': '720p',
            'height': 720,
            'bitrate': 1800000,
          },
        ],
        'fallback': {
          'url': 'https://cdn.example.com/video-3.mp4',
          'path': 'videos/video-3.mp4',
          'type': 'mp4',
          'quality': '480p',
          'height': 480,
          'bitrate': 900000,
        },
      },
    });

    expect(video.videoUrl, 'https://cdn.example.com/video-3.mp4');
    expect(video.playback?.version, 2);
    expect(video.playback?.mode, 'multi_rendition_mp4');
    expect(video.playback?.mp4Sources.map((source) => source.path), [
      'mp4/video-3/360p.mp4',
      'mp4/video-3/480p.mp4',
      'mp4/video-3/720p.mp4',
      'videos/video-3.mp4',
    ]);
    expect(video.sources.map((source) => source.url), [
      'https://cdn.example.com/mp4/video-3/360p.mp4',
      'https://cdn.example.com/mp4/video-3/480p.mp4',
      'https://cdn.example.com/mp4/video-3/720p.mp4',
      'https://cdn.example.com/video-3.mp4',
    ]);
    expect(video.hasMultipleMp4Sources, isTrue);
    expect(
      video.playback?.effectiveModeForSourceType('mp4'),
      'multi_rendition_mp4',
    );
  });

  test('prefers playback fallback over a stale top-level videoUrl', () {
    final video = Video.fromMap({
      'id': 'video-4',
      'videoUrl': 'https://cdn.example.com/videos/video-4.mp4',
      'playback': {
        'version': 2,
        'mode': 'multi_rendition_mp4',
        'sources': [
          {
            'url': 'https://cdn.example.com/mp4/video-4/360p.mp4',
            'path': 'mp4/video-4/360p.mp4',
            'type': 'mp4',
            'quality': '360p',
            'height': 360,
          },
          {
            'url': 'https://cdn.example.com/mp4/video-4/480p.mp4',
            'path': 'mp4/video-4/480p.mp4',
            'type': 'mp4',
            'quality': '480p',
            'height': 480,
          },
        ],
        'fallback': {
          'url': 'https://cdn.example.com/mp4/video-4/480p.mp4',
          'path': 'mp4/video-4/480p.mp4',
          'type': 'mp4',
          'quality': '480p',
          'height': 480,
        },
      },
    });

    expect(video.videoUrl, 'https://cdn.example.com/mp4/video-4/480p.mp4');
    expect(video.effectiveUrl, 'https://cdn.example.com/mp4/video-4/480p.mp4');
  });

  test('does not infer primary playback URL from non-MP4 fields', () {
    final video = Video.fromMap({
      'id': 'video-4b',
      'videoUrl': 'https://cdn.example.com/videos/video-4b.webm',
      'playback': {
        'version': 2,
        'mode': 'mp4_only',
        'sourceAsset': {
          'url': 'https://cdn.example.com/videos/video-4b.webm',
          'path': 'videos/video-4b.webm',
          'type': 'webm',
        },
        'fallback': {
          'url': 'https://cdn.example.com/videos/video-4b.webm',
          'path': 'videos/video-4b.webm',
          'type': 'webm',
        },
        'sources': [
          {
            'url': 'https://cdn.example.com/mp4/video-4b/480p.mp4',
            'path': 'mp4/video-4b/480p.mp4',
            'type': 'mp4',
            'quality': '480p',
            'height': 480,
          },
        ],
      },
    });

    expect(video.videoUrl, 'https://cdn.example.com/mp4/video-4b/480p.mp4');
    expect(video.sources.map((source) => source.url), [
      'https://cdn.example.com/mp4/video-4b/480p.mp4',
    ]);
  });

  test('parses canonical single-rendition MP4 contracts', () {
    final video = Video.fromMap({
      'id': 'video-5',
      'videoUrl': 'https://cdn.example.com/videos/video-5.mp4',
      'playback': {
        'version': 2,
        'mode': 'mp4_only',
        'sources': [
          {
            'url': 'https://cdn.example.com/videos/video-5.mp4',
            'path': 'videos/video-5.mp4',
            'type': 'mp4',
            'quality': '480p',
            'height': 480,
            'bitrate': 900000,
          },
        ],
        'sourceAsset': {
          'url': 'https://cdn.example.com/videos/video-5.mp4',
          'path': 'videos/video-5.mp4',
          'type': 'mp4',
          'quality': '480p',
          'height': 480,
          'bitrate': 900000,
        },
        'fallback': {
          'url': 'https://cdn.example.com/videos/video-5.mp4',
          'path': 'videos/video-5.mp4',
          'type': 'mp4',
          'quality': '480p',
          'height': 480,
          'bitrate': 900000,
        },
      },
      'sources': [
        {
          'url': 'https://cdn.example.com/videos/video-5.mp4',
          'path': 'videos/video-5.mp4',
          'type': 'mp4',
          'quality': '480p',
          'height': 480,
          'bitrate': 900000,
        },
      ],
    });

    expect(video.videoUrl, 'https://cdn.example.com/videos/video-5.mp4');
    expect(video.playback?.mode, 'mp4_only');
    expect(video.hasMultipleMp4Sources, isFalse);
    expect(video.playback?.mp4Sources.map((source) => source.path), [
      'videos/video-5.mp4',
    ]);
    expect(
      video.playback?.effectiveModeForSourceType('mp4'),
      'mp4_only',
    );
  });
}
