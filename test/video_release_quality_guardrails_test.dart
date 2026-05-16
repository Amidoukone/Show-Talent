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

    test('video report flow keeps auth failures controlled', () {
      final controller =
          File('lib/controller/video_controller.dart').readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();

      expect(controller, contains("'reportVideo'"));
      expect(controller, contains('callDataWithHttpFallback'));
      expect(controller, contains('_reportVideoWithFirestoreFallback'));
      expect(controller, contains('_isAuthAccessFailure'));
      expect(controller, contains('_authRequiredResponse'));
      expect(controller, contains("code: 'unauthenticated'"));
      expect(controller, contains("response.code == 'unauthenticated'"));
      expect(
        controller,
        contains('response.success ? ToastLevel.success : response.toast'),
      );
      expect(
        controller,
        isNot(contains(
            'response.success ? ToastLevel.success : ToastLevel.error')),
      );
      expect(rules, contains('function canReportVideo()'));
      expect(rules, contains('changesOnly(["reports", "reportCount"])'));
      expect(
        rules,
        contains('request.auth.uid in request.resource.data.reports'),
      );
      expect(rules, contains('allow update: if canReportVideo();'));
    });

    test('video captions stay separated from the action rail on small screens',
        () {
      final player =
          File('lib/widgets/smart_video_player.dart').readAsStringSync();
      final tiktokPlayer =
          File('lib/widgets/tiktok_video_player.dart').readAsStringSync();
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      final profileFeed =
          File('lib/screens/profile_video_feed_screen.dart').readAsStringSync();

      expect(player, contains('_buildVideoMetadataOverlay(context)'));
      expect(player, contains('_videoActionRailReservedWidth'));
      expect(player, contains('right: _videoActionRailReservedWidth'));
      expect(player, contains('media.viewPadding.bottom'));
      expect(player, contains('maxLines: _captionCollapsedMaxLines'));
      expect(player, contains("isExpanded ? 'Voir moins' : 'Voir plus'"));
      expect(player, contains('SingleChildScrollView'));
      expect(player, contains('_videoActionButtonExtent'));
      expect(tiktokPlayer, contains('bottom: _progressBottomOffset(context)'));
      expect(tiktokPlayer, contains('viewPadding.bottom'));

      expect(home, isNot(contains('FadeTransition')));
      expect(profileFeed, isNot(contains('bottom: 100')));
    });

    test('video runtime keeps MP4 as the only playback path', () {
      final player =
          File('lib/widgets/smart_video_player.dart').readAsStringSync();
      final manager = File('lib/widgets/video_manager.dart').readAsStringSync();
      final orchestrator =
          File('lib/videos/domain/video_focus_orchestrator.dart')
              .readAsStringSync();
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      final videoFeed =
          File('lib/screens/video_feed_screen.dart').readAsStringSync();
      final profileFeed =
          File('lib/screens/profile_video_feed_screen.dart').readAsStringSync();
      final profileScroll =
          File('lib/screens/profil_video_scrollview.dart').readAsStringSync();

      expect(manager, contains('final requestedHls = false;'));
      expect(orchestrator, contains('requestedHls: false'));
      expect(orchestrator, isNot(contains('useHlsForVideo')));
      expect(player, contains('preferHlsRequested: false'));
      expect(player, isNot(contains('_preferHls')));
      expect(player, isNot(contains('_forceMp4Fallback')));
      expect(home, isNot(contains('useHlsForVideo')));
      expect(videoFeed, isNot(contains('useHlsForVideo')));
      expect(profileFeed, isNot(contains('useHlsForVideo')));
      expect(profileScroll, isNot(contains('useHlsForVideo')));
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
      expect(tiktokPlayer, contains('_slowLoadingDelay'));
      expect(tiktokPlayer, contains('_syncSlowLoadingState'));
      expect(tiktokPlayer, contains('Connexion lente...'));
      expect(tiktokPlayer, contains('class _VideoGestureFeedback'));
      expect(tiktokPlayer, contains("wasPlaying ? 'Pause' : 'Lecture'"));
      expect(tiktokPlayer, contains('Alignment.centerLeft'));
      expect(tiktokPlayer, contains('Alignment.centerRight'));
      expect(tiktokPlayer, contains('Icons.forward_10_rounded'));
      expect(tiktokPlayer, contains('Icons.replay_10_rounded'));
      expect(tiktokPlayer, contains('TextButton.icon'));
      expect(tiktokPlayer, contains('FilledButton.icon'));
      expect(tiktokPlayer, contains("label: const Text('Réessayer')"));
    });
    test('visible video binds a newly ready managed controller without scroll',
        () {
      final smartPlayer =
          File('lib/widgets/smart_video_player.dart').readAsStringSync();

      expect(smartPlayer, contains('shouldBindManagedPlayer'));
      expect(
        smartPlayer,
        contains('managedPlayer != null && !identical(managedPlayer, _player)'),
      );
      expect(smartPlayer, contains('_bindPlayer(managedPlayer);'));
      expect(smartPlayer, contains('_scheduleMaybePlay();'));
    });
  });
}
