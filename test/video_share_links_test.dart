import 'package:adfoot/utils/video_share_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoShareLinks', () {
    test('builds stable public video URLs', () {
      expect(
        VideoShareLinks.buildVideoUrl('abc_123-def'),
        'https://adfoot.org/v/abc_123-def',
      );
    });

    test('rejects invalid video IDs before sharing', () {
      expect(VideoShareLinks.buildVideoUrl(''), isNull);
      expect(VideoShareLinks.buildVideoUrl('../secret'), isNull);
      expect(VideoShareLinks.buildVideoUrl('abc'), isNull);
    });

    test('extracts video IDs from public share links', () {
      expect(
        VideoShareLinks.extractVideoId(
          Uri.parse('https://adfoot.org/v/abc_123-def?utm=share'),
        ),
        'abc_123-def',
      );
    });

    test('ignores unsupported hosts and paths', () {
      expect(
        VideoShareLinks.extractVideoId(
          Uri.parse('https://firebasestorage.googleapis.com/v/abc_123-def'),
        ),
        isNull,
      );
      expect(
        VideoShareLinks.extractVideoId(
          Uri.parse('https://adfoot.org/videos/abc_123-def'),
        ),
        isNull,
      );
    });
  });
}
