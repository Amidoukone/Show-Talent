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
      expect(script, contains('adfoot-production'));
      expect(script, contains('FIREBASE_APP_CHECK_TOKEN'));
      expect(script, contains('X-Firebase-AppCheck'));
      expect(script, contains('FIREBASE_SMOKE_EMAIL'));
      expect(script, contains('signInWithPassword'));
      expect(script, contains('not-owned'));
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
      expect(content, contains("'videoId': videoId"));
      expect(content, contains("'autoplay': true"));
      expect(content, contains("if (error.code == 'unauthenticated')"));
      expect(
        content.indexOf("if (error.code == 'unauthenticated')"),
        lessThan(content.indexOf("final message = (error.message ?? '')")),
      );
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
      final rules = File('firestore.rules').readAsStringSync();

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
      expect(controller, contains('_shareVideoWithFirestoreFallback'));
      expect(controller, contains("response.code == 'resource-exhausted'"));
      expect(controller, contains('response.copyWith(toast: ToastLevel.info)'));
      expect(rules, contains('function canIncrementVideoShareCount()'));
      expect(rules, contains('changesOnly(["shareCount"])'));
      expect(
        rules,
        contains('allow update: if canIncrementVideoShareCount();'),
      );
    });

    test('video action rail keeps modern guarded interactions', () {
      final player =
          File('lib/widgets/smart_video_player.dart').readAsStringSync();
      final actionRail =
          File('lib/widgets/video_action_rail.dart').readAsStringSync();

      expect(player, contains('_isLikeActionLoading'));
      expect(player, contains('_isReportActionLoading'));
      expect(player, contains('_isDeleteActionLoading'));
      expect(player, contains('_isAddVideoActionLoading'));
      expect(player, contains('VideoActionRail('));
      expect(actionRail, contains('class VideoActionRail'));
      expect(actionRail, contains('VideoUiStrings.delete'));
      expect(actionRail, contains('VideoUiStrings.report'));
      expect(actionRail, contains('VideoUiStrings.profile'));
      expect(actionRail, contains('formatActionCount(video.likes.length)'));
      expect(actionRail, contains('formatActionCount(video.shareCount)'));
      expect(player, contains('_confirmReport'));
      expect(player, contains('_openAddVideo(videoController)'));
      expect(actionRail, contains('Semantics('));
      expect(actionRail, isNot(contains("label: '\${video.reportCount}'")));
    });

    test('video sensitive confirmations use a modern bottom sheet', () {
      final player =
          File('lib/widgets/smart_video_player.dart').readAsStringSync();
      final videoStrings =
          File('lib/utils/video_ui_strings.dart').readAsStringSync();

      expect(player, contains('showModalBottomSheet<void>'));
      expect(player, contains('_VideoActionConfirmationSheet'));
      expect(player, contains('DraggableScrollableSheet'));
      expect(player, contains('SafeArea('));
      expect(player, contains('FilledButton.icon'));
      expect(player, contains('OutlinedButton'));
      expect(player, contains('VideoUiStrings.deleteVideoSheetMessage'));
      expect(player, contains('VideoUiStrings.reportVideoSheetMessage'));
      expect(player, isNot(contains('AlertDialog(')));
      expect(player, isNot(contains('Get.dialog(')));
      expect(videoStrings, contains('deleteVideoPrimaryAction'));
      expect(videoStrings, contains('reportVideoPrimaryAction'));
      expect(videoStrings, contains('sensitiveActionWarning'));
    });

    test('video user-facing strings stay centralized', () {
      final controller =
          File('lib/controller/video_controller.dart').readAsStringSync();
      final videoFeed =
          File('lib/screens/video_feed_screen.dart').readAsStringSync();
      final profileFeed =
          File('lib/screens/profile_video_feed_screen.dart').readAsStringSync();
      final tiktokPlayer =
          File('lib/widgets/tiktok_video_player.dart').readAsStringSync();
      final videoStrings =
          File('lib/utils/video_ui_strings.dart').readAsStringSync();

      expect(videoFeed, contains('VideoUiStrings.emptyVideoFeedTitle'));
      expect(videoFeed, contains('VideoUiStrings.emptyVideoFeedMessage'));
      expect(
          profileFeed, contains('VideoUiStrings.emptyProfileVideoFeedTitle'));
      expect(
          profileFeed, contains('VideoUiStrings.emptyProfileVideoFeedMessage'));
      expect(profileFeed, contains('VideoUiStrings.back'));
      expect(controller, contains('VideoUiStrings.likeOffline'));
      expect(controller, contains('VideoUiStrings.reportOffline'));
      expect(controller, contains('VideoUiStrings.deleteOffline'));
      expect(controller, contains('VideoUiStrings.shareOffline'));
      expect(controller, contains('VideoUiStrings.videoNotFound'));
      expect(controller, contains('VideoUiStrings.reportUnavailable'));
      expect(
          tiktokPlayer, contains('VideoUiStrings.forwardTenSecondsFeedback'));
      expect(tiktokPlayer, contains('VideoUiStrings.rewindTenSecondsFeedback'));
      expect(videoStrings, contains('emptyVideoFeedTitle'));
      expect(videoStrings, contains('reportUnavailable'));
    });

    test('video feedback uses the branded professional surface', () {
      final feedback = File('lib/widgets/ad_feedback.dart').readAsStringSync();
      final toastWrappers =
          File('lib/screens/success_toast.dart').readAsStringSync();
      final actionResponse =
          File('lib/models/action_response.dart').readAsStringSync();

      expect(feedback, contains('Get.showSnackbar'));
      expect(feedback, contains('GetSnackBar'));
      expect(feedback, contains('SnackStyle.FLOATING'));
      expect(feedback, contains('AdColors.surfaceCard'));
      expect(feedback, contains('titleText: Text('));
      expect(feedback, contains('messageText: Padding('));
      expect(feedback, isNot(contains('Get.snackbar(')));
      expect(toastWrappers, contains('Action confirmée'));
      expect(toastWrappers, contains('Action impossible'));
      expect(toastWrappers, contains('À noter'));
      expect(actionResponse, contains('Action réalisée.'));
      expect(actionResponse, contains('Réessaie quand tu es en ligne.'));
      expect(actionResponse, isNot(contains('Ã')));
    });

    test('video like flow falls back to narrow Firestore toggle', () {
      final controller =
          File('lib/controller/video_controller.dart').readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();

      expect(controller, contains("'likeVideo'"));
      expect(controller, contains('_likeVideoWithFirestoreFallback'));
      expect(controller, contains("response.code == 'unauthenticated'"));
      expect(controller, contains('FieldValue.arrayUnion([userId])'));
      expect(controller, contains('FieldValue.arrayRemove([userId])'));
      expect(rules, contains('function canToggleVideoLike()'));
      expect(rules, contains('function canAddVideoLike()'));
      expect(rules, contains('function canRemoveVideoLike()'));
      expect(rules, contains('changesOnly(["likes"])'));
      expect(rules, contains('allow update: if canToggleVideoLike();'));
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
      final playbackControls =
          File('lib/widgets/video_playback_controls.dart').readAsStringSync();
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      final profileFeed =
          File('lib/screens/profile_video_feed_screen.dart').readAsStringSync();

      expect(player, contains('_buildVideoReadabilityScrim()'));
      expect(player, isNot(contains('heightFactor: 0.46')));
      expect(player, isNot(contains('alpha: 0.74')));
      expect(player, contains('_buildVideoMetadataOverlay(context)'));
      expect(player, contains('_buildPublisherAvatar'));
      expect(player, contains('_publisherInitials'));
      expect(player, contains('VideoActionRail.reservedWidth'));
      expect(player, contains('media.viewPadding.bottom'));
      expect(player, contains('maxLines: _captionCollapsedMaxLines'));
      expect(player, contains('VideoUiStrings.seeLess'));
      expect(player, contains('VideoUiStrings.seeMore'));
      expect(player, contains('SingleChildScrollView'));
      expect(
        File('lib/widgets/video_action_rail.dart').readAsStringSync(),
        contains('static const double buttonExtent = 48'),
      );
      expect(tiktokPlayer, contains('bottom: _progressBottomOffset(context)'));
      expect(playbackControls, contains('AdColors.brand'));
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

    test('video preload keeps active playback first and staggers cache work',
        () {
      final manager = File('lib/widgets/video_manager.dart').readAsStringSync();
      final orchestrator =
          File('lib/videos/domain/video_focus_orchestrator.dart')
              .readAsStringSync();

      expect(orchestrator, contains('await videoManager.pauseAllExcept'));
      expect(orchestrator, contains('videoManager.preloadSurrounding'));
      expect(manager, contains('_preloadRequestTokensByContext'));
      expect(manager, contains('_secondaryPreloadDelay'));
      expect(manager, contains('_preloadVideoAfterDelay'));
      expect(manager, contains('preloadPositionDelayForTests'));
      expect(manager, contains('preloadRadius: 2'));
      expect(manager, contains('preloadRadius: 3'));
    });

    test('video production observability covers playback actions and upload',
        () {
      final smartPlayer =
          File('lib/widgets/smart_video_player.dart').readAsStringSync();
      final videoController =
          File('lib/controller/video_controller.dart').readAsStringSync();
      final uploadController =
          File('lib/controller/upload_video_controller.dart')
              .readAsStringSync();
      final observability =
          File('lib/services/video_observability_service.dart')
              .readAsStringSync();

      expect(observability, contains('class VideoObservabilityService'));
      expect(observability, contains('logPlaybackError'));
      expect(observability, contains('logPlaybackRetry'));
      expect(observability, contains('logActionFailure'));
      expect(observability, contains('logUploadFailure'));
      expect(observability, contains("'play_error'"));
      expect(observability, contains("'retry'"));
      expect(observability, contains("'like_failed'"));
      expect(observability, contains("'share_failed'"));
      expect(observability, contains("'upload_failed'"));
      expect(smartPlayer, contains('_observability.logPlaybackError'));
      expect(smartPlayer, contains('_observability.logPlaybackRetry'));
      expect(videoController, contains('_observability.logActionFailure'));
      expect(uploadController, contains('_observability.logUploadFailure'));
      expect(uploadController, contains('_uploadDiagnostics'));
    });

    test('video playback failures keep a clear retry state', () {
      final smartPlayer =
          File('lib/widgets/smart_video_player.dart').readAsStringSync();
      final tiktokPlayer =
          File('lib/widgets/tiktok_video_player.dart').readAsStringSync();
      final stateOverlay =
          File('lib/widgets/video_state_overlay.dart').readAsStringSync();
      final playbackControls =
          File('lib/widgets/video_playback_controls.dart').readAsStringSync();
      final videoStrings =
          File('lib/utils/video_ui_strings.dart').readAsStringSync();

      expect(smartPlayer, contains("reason: 'runtime_value_error'"));
      expect(smartPlayer, contains('VideoUiStrings.playbackInterruptedRetry'));
      expect(tiktokPlayer, contains('Widget _buildSafeState'));
      expect(tiktokPlayer, contains('VideoStateOverlay.loading'));
      expect(tiktokPlayer, contains('VideoStateOverlay.error'));
      expect(stateOverlay, contains('VideoUiStrings.loadingMessage'));
      expect(videoStrings, contains('Chargement de la vid'));
      expect(tiktokPlayer, contains('_slowLoadingDelay'));
      expect(tiktokPlayer, contains('_syncSlowLoadingState'));
      expect(videoStrings, contains('Connexion lente...'));
      expect(stateOverlay, contains('borderRadius: BorderRadius.circular(16)'));
      expect(tiktokPlayer, contains('class _VideoGestureFeedback'));
      expect(tiktokPlayer, contains('_buildCenterPlaybackIndicator'));
      expect(tiktokPlayer, contains('hidePlayPauseIcon'));
      expect(tiktokPlayer, contains('VideoUiStrings.pause'));
      expect(tiktokPlayer, contains('VideoUiStrings.play'));
      expect(tiktokPlayer, contains('VideoPlaybackControls'));
      expect(tiktokPlayer, contains('VideoProgressBar'));
      expect(tiktokPlayer, isNot(contains('Widget _iconButton')));
      expect(playbackControls, contains('class VideoPlaybackControls'));
      expect(playbackControls, contains('class VideoProgressBar'));
      expect(playbackControls, contains('class VideoPlaybackSpeedSheet'));
      expect(playbackControls, contains('Semantics('));
      expect(playbackControls, contains('Tooltip('));
      expect(playbackControls, contains('SingleChildScrollView'));
      expect(playbackControls, contains('selected: selected'));
      expect(videoStrings, contains('progressBarSemantic'));
      expect(videoStrings, contains('playbackProgressValue'));
      expect(videoStrings, contains('formatPlaybackSpeed'));
      expect(tiktokPlayer, contains('_playbackSpeed'));
      expect(tiktokPlayer, contains('_applyPlaybackSpeed'));
      expect(tiktokPlayer, contains('VideoPlaybackSpeedSheet'));
      expect(tiktokPlayer, isNot(contains('children: [0.75, 1.0, 1.5, 2.0]')));
      expect(tiktokPlayer, contains('Alignment.centerLeft'));
      expect(tiktokPlayer, contains('Alignment.centerRight'));
      expect(tiktokPlayer, contains('Icons.forward_10_rounded'));
      expect(tiktokPlayer, contains('Icons.replay_10_rounded'));
      expect(stateOverlay, contains('TextButton.icon'));
      expect(stateOverlay, contains('FilledButton.icon'));
      expect(stateOverlay, contains('retryLabel'));
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

    test('home video search stays separate from the live feed state', () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();

      expect(
          home, contains('List<Video> get _currentVideos => _isSearchActive'));
      expect(home, contains('_searchResults.toList(growable: false)'));
      expect(
          home, contains('videoController.videoList.toList(growable: false)'));
      expect(home, contains('if (_isSearchActive) {'));
      expect(home, contains('return;'));
      expect(home, contains('_feedIndexBeforeSearch'));
      expect(home, contains('_jumpToPageSilently(restoreIndex)'));
      expect(home, contains('whereIn: batch'));
    });

    test('home route refresh focuses uploaded video before autoplay', () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();

      expect(home, contains('_captureRoutePlaybackRequest'));
      expect(home, contains("_routeFocusVideoId = rawVideoId.trim();"));
      expect(home, contains('_ensureFocusedVideoVisible'));
      expect(home, contains('focusVideoId: _routeFocusVideoId'));
      expect(home, contains('Video.fromDoc(doc)'));
      expect(home, contains('_activateHomeIndex(targetIndex'));
    });

    test('home profile action uses a professional generated avatar fallback',
        () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();

      expect(home, isNot(contains("assets/default_avatar.jpg")));
      expect(home, contains('_buildHomeProfileAvatar'));
      expect(home, contains('_profileInitials'));
      expect(home, contains('_buildProfileInitialsSurface'));
      expect(home, contains('Image.network'));
      expect(home, contains('errorBuilder'));
      expect(home, contains('Icons.sports_soccer_rounded'));
      expect(home, contains('Semantics('));
    });
  });
}
