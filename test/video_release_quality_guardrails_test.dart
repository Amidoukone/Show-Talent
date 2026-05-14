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

    test('video feed screen releases its contextual controller on dispose', () {
      final content =
          File('lib/screens/video_feed_screen.dart').readAsStringSync();

      expect(content,
          contains('FeatureControllerRegistry.ensureVideoController('));
      expect(
        content,
        contains(
            'FeatureControllerRegistry.releaseVideoController(widget.contextKey);'),
      );
    });

    test('video share flow only records a completed share attempt', () {
      final player =
          File('lib/widgets/smart_video_player.dart').readAsStringSync();
      final controller =
          File('lib/controller/video_controller.dart').readAsStringSync();

      expect(player, contains('ShareResultStatus.dismissed'));
      expect(player, contains('ShareResultStatus.unavailable'));
      expect(player, contains('widget.video.effectiveUrl.trim()'));
      expect(player, contains('_buildShareText(shareUrl)'));
      expect(player, contains('sharePositionOrigin: _sharePositionOrigin()'));
      expect(player, contains('controller.partagerVideo(widget.video.id)'));
      expect(
          player, isNot(contains('ShareParams(text: \'Regarde cette vidéo :')));
      expect(player, isNot(contains('(widget.video.shareCount + 1)')));

      expect(controller, contains("'shareVideo'"));
      expect(controller, contains("response.code == 'resource-exhausted'"));
      expect(controller, contains('response.copyWith(toast: ToastLevel.info)'));
    });

    test('video playback failures keep a clear retry state', () {
      final smartPlayer =
          File('lib/widgets/smart_video_player.dart').readAsStringSync();
      final tiktokPlayer =
          File('lib/widgets/tiktok_video_player.dart').readAsStringSync();

      expect(smartPlayer, contains("reason: 'runtime_value_error'"));
      expect(smartPlayer, contains('Lecture interrompue. Réessayez.'));
      expect(tiktokPlayer, contains('Widget _buildSafeState'));
      expect(tiktokPlayer, contains('Préparation de la vidéo...'));
      expect(tiktokPlayer, contains('FilledButton.icon'));
      expect(tiktokPlayer, contains("label: const Text('Réessayer')"));
    });
  });
}
