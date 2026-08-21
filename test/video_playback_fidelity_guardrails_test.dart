import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adfoot/models/video.dart';
import 'package:adfoot/widgets/tiktok_video_player.dart';

/// Three failures that all made the app quietly betray the video the user
/// actually filmed, and one that made an action do nothing at all.
///
/// Every one of them was reported by a user before it was ever visible to us:
/// the heart did nothing, the picture came back softer than the file in the
/// gallery, and the play on the left and right touchlines was simply gone.
void main() {
  group('a like can always be applied optimistically', () {
    // Production stack traces: UnmodifiableListMixin.removeWhere, thrown from
    // _setLocalLikeState out of an unawaited callback. Nothing surfaced to the
    // user; the heart just never changed.
    test('likes stay mutable when the document carries no likes field', () {
      final video = Video.fromMap({
        'id': 'v1',
        'videoUrl': 'https://example.test/clip.mp4',
        'uid': 'author',
      });

      expect(video.likes, isEmpty);
      expect(() => video.likes.add('viewer'), returnsNormally);
      expect(() => video.likes.remove('viewer'), returnsNormally);
      expect(() => video.likes.removeWhere((id) => true), returnsNormally);
    });

    test('reports stay mutable when the document carries no reports field', () {
      final video = Video.fromMap({
        'id': 'v1',
        'videoUrl': 'https://example.test/clip.mp4',
        'uid': 'author',
      });

      expect(() => video.reports.add('viewer'), returnsNormally);
    });

    test('a caller passing a const list does not poison the model', () {
      final video = Video(
        id: 'v1',
        videoUrl: 'https://example.test/clip.mp4',
        thumbnailUrl: '',
        description: '',
        caption: '',
        profilePhoto: '',
        uid: 'author',
        likes: const <String>[],
        reports: const <String>[],
      );

      expect(() => video.likes.add('viewer'), returnsNormally);
      expect(() => video.reports.add('viewer'), returnsNormally);
    });

    test('existing likes are preserved, and copied rather than aliased', () {
      final source = <String>['a', 'b'];
      final video = Video(
        id: 'v1',
        videoUrl: 'https://example.test/clip.mp4',
        thumbnailUrl: '',
        description: '',
        caption: '',
        profilePhoto: '',
        uid: 'author',
        likes: source,
      );

      expect(video.likes, ['a', 'b']);

      video.likes.add('c');
      expect(source, ['a', 'b'], reason: 'the caller list must not be mutated');
    });

    test('new videos are created with the social counters already present', () {
      final uploadSession =
          File('functions/src/upload_session.ts').readAsStringSync();

      // Seeded on the document's only creation point, and only there: a
      // finalize retry must never be able to reset real counts.
      expect(uploadSession, contains('likes: [],'));
      expect(uploadSession, contains('reports: [],'));
      expect(uploadSession, contains('reportCount: 0,'));
      expect(uploadSession, contains('shareCount: 0,'));
    });
  });

  group('the frame is shown whole unless cropping is nearly free', () {
    const portraitViewport = Size(1080, 1920);

    BoxFit fitFor(double width, double height) {
      return TiktokVideoPlayer.resolveVideoFit(
        videoWidth: width,
        videoHeight: height,
        viewportWidth: portraitViewport.width,
        viewportHeight: portraitViewport.height,
      );
    }

    test('a landscape clip is letterboxed, not cropped to a sliver', () {
      // BoxFit.cover on 16:9 inside 9:16 discards ~68% of the picture width --
      // both touchlines, which in football footage is where the play is.
      expect(fitFor(1920, 1080), BoxFit.contain);
      expect(fitFor(1024, 576), BoxFit.contain);
    });

    test('a square clip is letterboxed', () {
      expect(fitFor(1080, 1080), BoxFit.contain);
    });

    test('a portrait clip still fills the screen', () {
      expect(fitFor(1080, 1920), BoxFit.cover);
      expect(fitFor(720, 1280), BoxFit.cover);
    });

    test('a near-9:16 export is not letterboxed over a few pixels', () {
      expect(fitFor(1080, 1912), BoxFit.cover);
    });

    test('unknown dimensions keep the previous full-bleed behaviour', () {
      expect(fitFor(0, 0), BoxFit.cover);
      expect(
        TiktokVideoPlayer.resolveVideoFit(
          videoWidth: 1080,
          videoHeight: 1920,
          viewportWidth: 0,
          viewportHeight: 0,
        ),
        BoxFit.cover,
      );
      expect(fitFor(double.nan, 1920), BoxFit.cover);
    });
  });

  group('the optimizer preserves what the phone recorded', () {
    late String optimizer;

    setUpAll(() {
      optimizer = File('functions/src/index.ts').readAsStringSync();
    });

    test('the resolution ceiling is 1080p, and only a ceiling', () {
      // The old ladder stopped at 720p *and* picked the largest preset below
      // the source's short edge, so 1024x576 came back as 853x480.
      expect(optimizer, contains('MAX_OUTPUT_SHORT_EDGE'));
      expect(optimizer, contains('process.env.MAX_OUTPUT_SHORT_EDGE'));
      expect(optimizer, contains('label: "1080p"'));

      // The clamp used to read `Math.min(shortEdge, MAX_OUTPUT_SHORT_EDGE)`
      // inline. It moved into buildMp4RenditionForCeiling when the companion
      // rendition started sharing the same scaling rules, so the guarantee is
      // now pinned in two halves: the clamp can still only ever scale *down*,
      // and the delivered asset is still the one built at the 1080p ceiling.
      // A companion ceiling silently substituted here is exactly the
      // regression that would bring "les videos reviennent floues" back.
      expect(
        optimizer,
        contains('Math.min(shortEdge, ceiling)'),
        reason: 'a source within the ceiling must keep its own dimensions',
      );
      expect(
        optimizer,
        contains(
          'return buildMp4RenditionForCeiling(\n'
          '    sourceWidth,\n'
          '    sourceHeight,\n'
          '    MAX_OUTPUT_SHORT_EDGE,\n'
          '  );',
        ),
        reason: 'the delivered asset is built at the full ceiling, not a companion one',
      );
      expect(
        optimizer,
        contains('const fallbackMp4Rendition = buildSingleMp4Rendition('),
        reason: 'and it is that builder the delivered asset goes through',
      );
    });

    test('the rate preset is chosen at or above the output size', () {
      expect(
        optimizer,
        contains('candidate.height >= outputShortEdge'),
        reason: 'picking a preset below the output starves it of bitrate',
      );
    });

    test('quality is driven by CRF, with bitrate only as a cap', () {
      expect(optimizer, contains('-crf '));
      expect(optimizer, contains('-maxrate '));
      expect(
        optimizer,
        isNot(contains('`-b:v ')),
        reason: 'a fixed average bitrate is what softened heavy clips',
      );
    });

    test('an already-streamable upload is remuxed, never re-encoded', () {
      // Re-encoding a fine H.264/AAC MP4 is pure generation loss.
      expect(optimizer, contains('shouldRemuxWithoutReencoding'));
      expect(optimizer, contains('function remuxMp4('));
      expect(optimizer, contains('"-c copy"'));
      expect(
        optimizer,
        contains('"-movflags +faststart"'),
        reason: 'playback must still start before the file is fully fetched',
      );
    });

    test('the passthrough contract advertises the delivered asset', () {
      // The rendition ceiling would misreport what viewers actually receive,
      // and the feed-quality metrics read these fields.
      expect(optimizer, contains('deliveredRendition'));
    });

    test('the probe reads codecs, not just dimensions', () {
      expect(optimizer, contains('videoCodec'));
      expect(optimizer, contains('audioCodec'));
      expect(optimizer, contains('parseProbedMediaFromFfmpegLog'));
    });
  });
}
