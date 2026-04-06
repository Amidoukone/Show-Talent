import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Video release quality guardrails', () {
    test('smoke script enforces upload to ready to playback to delete flow',
        () {
      final script = File('scripts/smoke-upload-flow.ps1').readAsStringSync();

      expect(script, contains('createUploadSession'));
      expect(script, contains('requestThumbnailUploadUrl'));
      expect(script, contains('finalizeUpload'));
      expect(script, contains('Wait-VideoReady'));
      expect(script, contains('Get-PlayableUrls'));
      expect(script, contains('Probe-PlaybackUrl'));
      expect(script, contains('deleteVideo'));
      expect(script, contains('Get-FirestoreVideoDoc'));
      expect(
          script, contains('Video document still exists after deleteVideo.'));
    });

    test('upload controller keeps strict ready+optimized gate', () {
      final content = File('lib/controller/upload_video_controller.dart')
          .readAsStringSync();

      expect(content, contains("status == 'ready' && optimized"));
      expect(content,
          contains("const failureStatuses = {'error', 'failed', 'failure'};"));
      expect(content,
          contains('await _waitForVideoStatusReady(session.sessionId);'));
    });

    test('video controller delete flow preserves runtime consistency', () {
      final content =
          File('lib/controller/video_controller.dart').readAsStringSync();

      expect(content, contains('await videoManager.pauseAll(contextKey);'));
      expect(
          content,
          contains(
              'await videoManager.disposeUrls(contextKey, [removedUrl]);'));
      expect(content, contains('currentIndex.value = -1;'));
      expect(content, contains('clamp(0, videoList.length - 1)'));
      expect(content, contains('_prefetchThumbnailsAround(clampedIndex);'));
    });
  });
}
