import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrails for the companion rendition.
///
/// A *second*, lighter MP4 published beside the delivered asset so the
/// adaptive selector the app already ships has something to choose from on a
/// weak network. The delivered asset does not change: same pixels, same
/// bitrate, passthrough included.
///
/// Every test here pins a way this feature could quietly damage production
/// while looking like it works.
String _read(String path) => File(path).readAsStringSync();

void main() {
  late String index;
  late String actions;

  setUpAll(() {
    index = _read('functions/src/index.ts');
    actions = _read('functions/src/actions.ts');
  });

  group('the companion never touches the delivered asset', () {
    test('it ships disabled', () {
      expect(
        index,
        contains(
          'const COMPANION_RENDITION_ENABLED =\n'
          '  process.env.COMPANION_RENDITION_ENABLED === "true";',
        ),
        reason: 'anything but an explicit "true" must leave production as-is',
      );
      expect(
        _read('functions/.env.production.example'),
        contains('COMPANION_RENDITION_ENABLED=false'),
      );
    });

    // The quality decisions that fixed "les videos reviennent floues" are not
    // this feature's to revisit. The companion is additive or it is nothing.
    test('the quality ceilings are untouched', () {
      expect(index, contains('process.env.MAX_OUTPUT_SHORT_EDGE,\n  1080,'));
      expect(index, contains('process.env.MAX_PASSTHROUGH_BITRATE,\n  12000000,'));
      expect(index, contains('process.env.OUTPUT_CRF, 20'));
    });

    // playback.fallback, playback.sourceAsset and any consumer reading
    // sources.first must keep resolving to the full-quality asset.
    test('the primary source stays first and stays the fallback', () {
      expect(index, contains('const mp4Sources: PlaybackSource[] = [fallbackSource];'));
      expect(index, contains('mp4Sources.push(companionSource);'));
      expect(
        index,
        contains('buildPlaybackContract(\n        mp4Sources,\n        fallbackSource,\n      )'),
      );
    });

    // A lighter fallback is never worth failing an upload over: the delivered
    // asset is already uploaded and contracted before this runs.
    test('a failed companion does not fail the optimization', () {
      final companionIndex = index.indexOf('if (companionRendition) {');
      expect(companionIndex, isNonNegative);

      final block = index.substring(companionIndex);
      expect(block.indexOf('} catch (companionError) {'), isNonNegative);
      expect(
        block.indexOf('Companion rendition skipped:'),
        isNonNegative,
        reason: 'the failure is logged and swallowed, not propagated',
      );
      expect(
        block.substring(0, block.indexOf('} catch (companionError) {')),
        isNot(contains('status: "error"')),
      );
    });
  });

  group('the companion cannot re-enter the pipeline', () {
    // optimizeMp4Video triggers on every finalized videos/**.mp4. Publishing
    // a companion there would re-enter this function with a videoId of
    // "{videoId}_something" and merge a ghost document into the videos
    // collection -- set({optimized: true}, {merge: true}) *creates* it.
    test('renditions are published outside the trigger prefix', () {
      expect(index, contains('return `mp4/\${videoId}/\${fileName}`;'));
      expect(index, contains('destination: companionPath,'));

      final pathBuilder = index.indexOf('function buildRenditionObjectPath(');
      expect(pathBuilder, isNonNegative);
      expect(
        index.substring(pathBuilder, index.indexOf('}', pathBuilder)),
        isNot(contains('videos/')),
      );
    });

    test('the trigger prefix it must stay out of is still videos/', () {
      expect(index, contains('!filePath.startsWith("videos/") ||'));
    });

    test('storage rules already serve and protect that prefix', () {
      final rules = _read('storage.rules');

      expect(rules, contains('match /mp4/{videoId}/{fileName} {'));
      expect(rules, contains('isOwnedMp4Rendition(videoId, fileName)'));
    });
  });

  group('a companion is never an orphan', () {
    // The owner-facing deleteVideo only ever collected four fixed paths plus
    // data.storagePath -- it never walked `sources`, unlike the admin path.
    // Every extra rendition would have stayed in the bucket forever: billed,
    // publicly readable, reachable only by a manual sweep.
    test('owner deletion collects rendition paths', () {
      expect(actions, contains('function collectSourceRecords('));
      expect(actions, contains("prefix: \"mp4/\","));

      final collector = actions.indexOf('function collectOwnedVideoAssetPaths(');
      expect(collector, isNonNegative);
      expect(
        actions.substring(collector),
        contains('for (const source of collectSourceRecords(data)) {'),
      );
    });

    test('owner deletion reads both the flat array and the contract', () {
      final records = actions.indexOf('function collectSourceRecords(');
      expect(records, isNonNegative);

      final body = actions.substring(records);
      expect(body, contains('data.sources'));
      expect(body, contains('contract.sourceAsset'));
      expect(body, contains('contract.fallback'));
      expect(body, contains('contract.sources'));
    });

    test('admin deletion already covered the prefix', () {
      final adminActions = _read('functions/src/admin_content_actions.ts');

      expect(adminActions, contains('path.startsWith("mp4/")'));
    });
  });

  group('the companion is only built when it would be used', () {
    test('it refuses to upscale or to match the primary', () {
      expect(
        index,
        contains(
          'if (Math.min(media.width, media.height) <= COMPANION_RENDITION_HEIGHT) {',
        ),
      );
    });

    test('it skips sources that already stream anywhere', () {
      expect(index, contains('COMPANION_MIN_SOURCE_BITRATE'));
      expect(
        index,
        contains('if (delivered === null || delivered < COMPANION_MIN_SOURCE_BITRATE) {'),
      );
    });

    // On the passthrough path the rendition ceiling describes an encode that
    // never ran; the number that matters is what viewers actually pull.
    test('the bitrate it tests is the delivered one', () {
      expect(index, contains('function deliveredBitrate('));
      expect(index, contains('return media?.bitrate ?? null;'));
    });

    test('it reuses the primary scaling rules rather than its own', () {
      expect(index, contains('function buildMp4RenditionForCeiling('));
      expect(
        index,
        contains(
          'return buildMp4RenditionForCeiling(\n'
          '    sourceWidth,\n'
          '    sourceHeight,\n'
          '    MAX_OUTPUT_SHORT_EDGE,\n'
          '  );',
        ),
        reason: 'the primary must go through the same builder as the companion',
      );
    });
  });
}
