import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Video release quality guardrails', () {
    test(
      'smoke script enforces upload to review to playback to delete flow',
      () {
        final script = File('scripts/smoke-upload-flow.ps1').readAsStringSync();

        expect(script, contains('createUploadSession'));
        expect(script, contains(r'fileSizeBytes = $videoSize'));
        expect(script, contains('requestThumbnailUploadUrl'));
        expect(script, contains('finalizeUpload'));
        expect(script, contains('Wait-VideoUnderReview'));
        expect(script, contains('status=under_review'));
        expect(script, contains('moderationStatus=pending'));
        expect(script, contains('visibility=private'));
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
          script,
          contains('Video document still exists after deleteVideo.'),
        );
      },
    );

    test('upload controller keeps strict ready+optimized gate', () {
      final content = File(
        'lib/controller/upload_video_controller.dart',
      ).readAsStringSync();
      final errorMapper = File(
        'lib/services/videos/upload_video_error_mapper.dart',
      ).readAsStringSync();
      final uploadClient = File(
        'lib/services/videos/data/upload_client.dart',
      ).readAsStringSync();
      final uploadRepository = File(
        'lib/services/videos/upload_video_repository.dart',
      ).readAsStringSync();

      expect(content, contains("status == 'ready' && optimized"));
      expect(
        content,
        contains("const failureStatuses = {'error', 'failed', 'failure'};"),
      );
      expect(
        content,
        contains('await _waitForVideoStatusReady(session.sessionId);'),
      );
      expect(content, contains("optimized && status == 'under_review'"));
      expect(content, contains('VideoUiStrings.uploadSubmittedForReview'));
      expect(content, isNot(contains("'videoId': videoId")));
      expect(content, isNot(contains("'autoplay': true")));
      // Through the service, not the Firebase SDK: controllers must keep
      // Firebase access behind services (see architecture_guardrails_test).
      expect(content, contains('_authSessionService.currentUid'));
      expect(content, isNot(contains('FirebaseAuth.instance')));
      expect(content, contains('Get.isRegistered<UserController>()'));
      expect(content, contains('_resolveCurrentUploadUser'));
      expect(content, contains('ensureCurrentUserHydrated(force: true)'));
      expect(content, contains('VideoUiStrings.uploadStageLoadProfile'));
      expect(content, contains('UploadVideoErrorMapper.toUserMessage(error)'));
      expect(errorMapper, contains("if (error.code == 'unauthenticated')"));
      expect(
        errorMapper.indexOf("if (error.code == 'unauthenticated')"),
        lessThan(errorMapper.indexOf("final message = (error.message ?? '')")),
      );
      expect(errorMapper, contains('_isTransientCallableCode'));
      expect(uploadClient, contains("'resource-exhausted',"));
      expect(uploadRepository, contains('processingReadTimeout'));
      expect(uploadRepository, contains('processingWatchTimeout'));
      expect(uploadRepository, contains('.timeout(processingReadTimeout)'));
    });

    test('upload callables use production-safe runtime options', () {
      final runtime = File(
        'functions/src/function_runtime.ts',
      ).readAsStringSync();
      final uploadSession = File(
        'functions/src/upload_session.ts',
      ).readAsStringSync();

      expect(runtime, contains('UPLOAD_CALLABLE_OPTIONS'));
      expect(runtime, contains('UPLOAD_CALLABLE_MIN_INSTANCES'));
      expect(runtime, contains('UPLOAD_CALLABLE_TIMEOUT_SECONDS'));
      // The warm instance must not be tied to the App Check posture: the
      // upload callables sit on the critical path of the app's core feature
      // whether or not attestation is enforced. Coupling them meant relaxing
      // App Check silently reintroduced cold starts.
      expect(runtime, isNot(contains('ENFORCE_APP_CHECK ? 1 : 0')));
      expect(runtime, contains('APP_CHECK_MODE'));
      expect(runtime, contains('logAppCheckState'));
      expect(uploadSession, contains('UPLOAD_CALLABLE_OPTIONS'));
      expect(uploadSession, contains('createUploadSession = onCall('));
      expect(uploadSession, contains('requestThumbnailUploadUrl = onCall('));
      expect(uploadSession, contains('finalizeUpload = onCall('));
      expect(uploadSession, isNot(contains('LOW_CPU_CALLABLE_OPTIONS')));
    });

    test('finalizeUpload is idempotent for the owner', () {
      final uploadSession = File(
        'functions/src/upload_session.ts',
      ).readAsStringSync();
      final uploadClient = File(
        'lib/services/videos/data/upload_client.dart',
      ).readAsStringSync();

      // A retried finalize whose first attempt already succeeded must report
      // success, not failed-precondition: production logs showed a user told
      // their upload had failed while the video was already ready, optimized
      // and public. The protection is "perform no write", not "throw".
      expect(uploadSession, contains('alreadyFinalized: true'));

      final finalizeIndex = uploadSession.indexOf('finalizeUpload = onCall(');
      expect(finalizeIndex, isNonNegative);

      // Comments are stripped first: the explanation above the guard quotes
      // the old error message on purpose, and matching it there would make
      // this assertion pass or fail on prose rather than on code.
      final finalizeCode = uploadSession
          .substring(finalizeIndex)
          .split('\n')
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('//') && !trimmed.startsWith('*');
          })
          .join('\n');
      expect(finalizeCode, isNot(contains('Session upload deja finalisee')));

      // Client-side net for the window where an older app build still talks
      // to a backend that predates the server fix.
      expect(uploadClient, contains('_isAlreadyFinalizedError'));
      expect(uploadClient, contains('_alreadyFinalizedPattern'));
    });

    test('video optimization is not serialized to a single instance', () {
      final index = File('functions/src/index.ts').readAsStringSync();
      final productionEnv = File(
        'functions/.env.production.example',
      ).readAsStringSync();

      // maxInstances: 1 was a throughput ceiling, not a cost control: with no
      // minInstances an idle optimizer costs nothing at any cap, so pinning it
      // at 1 only queued every upload behind the previous one.
      expect(index, contains('OPTIMIZE_MAX_INSTANCES'));
      expect(index, contains('maxInstances: OPTIMIZE_MAX_INSTANCES'));
      expect(index, isNot(contains('maxInstances: 1,')));
      expect(productionEnv, contains('OPTIMIZE_MAX_INSTANCES='));
    });

    test('push notification copy is normalized before FCM send', () {
      final actions = File('functions/src/actions.ts').readAsStringSync();
      final adminActions = File(
        'functions/src/admin_content_actions.ts',
      ).readAsStringSync();
      final notificationText = File(
        'functions/src/notification_text.ts',
      ).readAsStringSync();

      expect(notificationText, contains('function normalizeNotificationText'));
      expect(notificationText, contains(r'\u00c3\u00a9'));
      expect(notificationText, contains(r'\u2019'));
      expect(
        actions,
        contains(
          'import {normalizeNotificationText} from "./notification_text";',
        ),
      );
      expect(
        adminActions,
        contains(
          'import {normalizeNotificationText} from "./notification_text";',
        ),
      );
      expect(
        actions,
        contains('title: normalizeNotificationText(params.title, 120)'),
      );
      expect(
        actions,
        contains('body: normalizeNotificationText(params.body, 300)'),
      );
      expect(
        actions,
        contains(
          'const title = normalizeNotificationText(getString(request.data, "title"), 120);',
        ),
      );
      expect(
        actions,
        contains(
          'const body = normalizeNotificationText(getString(request.data, "body"), 300);',
        ),
      );
      expect(
        adminActions,
        contains('title: normalizeNotificationText(params.title, 120)'),
      );
      expect(
        adminActions,
        contains('body: normalizeNotificationText(params.body, 300)'),
      );
      expect(actions, contains('"Une nouvelle offre a ete publiee."'));
      expect(actions, contains('"Nouvel evenement"'));
      expect(actions, contains('"Un nouvel evenement est disponible."'));
    });

    test('video controller delete flow preserves runtime consistency', () {
      final content = File(
        'lib/controller/video_controller.dart',
      ).readAsStringSync();

      expect(content, contains('await videoManager.pauseAll(contextKey);'));
      expect(
        content,
        contains('await videoManager.disposeUrls(contextKey, [removedUrl]);'),
      );
      expect(content, contains('currentIndex.value = -1;'));
      expect(content, contains('clamp(0, videoList.length - 1)'));
      expect(content, contains('_prefetchThumbnailsAround(clampedIndex);'));
    });

    test('video feed screen releases its contextual controller on dispose', () {
      final content = File(
        'lib/screens/video_feed_screen.dart',
      ).readAsStringSync();

      expect(
        content,
        contains('FeatureControllerRegistry.ensureVideoController('),
      );
      expect(
        content,
        contains(
          'FeatureControllerRegistry.releaseVideoController(widget.contextKey);',
        ),
      );
    });

    test('video share flow only records a completed share attempt', () {
      final player = File(
        'lib/widgets/smart_video_player.dart',
      ).readAsStringSync();
      final controller = File(
        'lib/controller/video_controller.dart',
      ).readAsStringSync();
      final repository = File(
        'lib/services/videos/video_repository.dart',
      ).readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();
      final hosting = File('firebase.json').readAsStringSync();
      final functionsIndex = File('functions/src/index.ts').readAsStringSync();
      final sharePage = File(
        'functions/src/video_share_page.ts',
      ).readAsStringSync();
      final publicIndex = File('site_pub/index.html').readAsStringSync();
      final androidDownloadPage = File(
        'site_pub/download/android/index.html',
      ).readAsStringSync();
      final linkHandler = File(
        'lib/services/email_link_handler.dart',
      ).readAsStringSync();
      final loginScreen = File(
        'lib/screens/login_screen.dart',
      ).readAsStringSync();

      expect(player, contains('ShareResultStatus.dismissed'));
      expect(player, contains('ShareResultStatus.unavailable'));
      expect(
        player,
        contains('VideoShareLinks.buildVideoUrl(widget.video.id)'),
      );
      expect(player, contains('_buildShareText(shareUrl)'));
      expect(player, contains('sharePositionOrigin: _sharePositionOrigin()'));
      expect(player, contains('controller.partagerVideo(widget.video.id)'));
      expect(player, isNot(contains('widget.video.effectiveUrl.trim()')));
      expect(
        player,
        isNot(contains('ShareParams(text: \'Regarde cette vidéo :')),
      );
      expect(player, isNot(contains('(widget.video.shareCount + 1)')));

      expect(controller, contains("'shareVideo'"));
      expect(controller, contains('_shareVideoWithFirestoreFallback'));
      expect(repository, contains('shareVideoWithFirestoreFallback'));
      expect(repository, contains('FieldValue.increment(1)'));
      expect(controller, contains("response.code == 'resource-exhausted'"));
      expect(controller, contains('response.copyWith(toast: ToastLevel.info)'));
      expect(rules, contains('function canIncrementVideoShareCount()'));
      expect(rules, contains('changesOnly(["shareCount"])'));
      expect(
        rules,
        contains('allow update: if canIncrementVideoShareCount();'),
      );
      expect(hosting, contains('"source": "/v/**"'));
      expect(hosting, contains('"functionId": "videoSharePage"'));
      expect(hosting, contains('"source": "/download/android"'));
      expect(functionsIndex, contains('videoSharePage'));
      expect(sharePage, contains('intent://'));
      expect(sharePage, contains('ANDROID_APP_DOWNLOAD_URL'));
      expect(sharePage, contains("Ouvrir dans l'application"));
      expect(sharePage, contains('Vidéo de talent'));
      expect(sharePage, contains('Télécharger l’application'));
      expect(sharePage, isNot(contains('Regarde cette video')));
      expect(sharePage, isNot(contains('Video de talent')));
      expect(publicIndex, contains('href="/styles.css"'));
      expect(publicIndex, contains('src="/images/hero.jpg"'));
      expect(androidDownloadPage, contains("Application en accès contrôlé"));
      expect(linkHandler, contains('VideoShareLinks.extractVideoId(link)'));
      expect(linkHandler, contains("'videoId': videoId"));
      expect(loginScreen, contains('_postLoginRouteArguments'));
    });

    test('public site image references exist in hosting assets', () {
      final publicIndex = File('site_pub/index.html').readAsStringSync();
      final imageRefs = RegExp(
        r'src="/(images/[^"]+)"',
      ).allMatches(publicIndex).map((match) => match.group(1)!).toSet();

      expect(imageRefs, isNotEmpty);
      for (final imageRef in imageRefs) {
        expect(
          File('site_pub/$imageRef').existsSync(),
          isTrue,
          reason: 'Missing public hosting image asset: $imageRef',
        );
      }
    });

    test('video action rail keeps modern guarded interactions', () {
      final player = File(
        'lib/widgets/smart_video_player.dart',
      ).readAsStringSync();
      final actionRail = File(
        'lib/widgets/video_action_rail.dart',
      ).readAsStringSync();

      expect(player, contains('_isLikeActionLoading'));
      expect(player, contains('_queuedLikeTarget'));
      expect(player, contains('isLikeLoading: false'));
      expect(player, contains('_setLocalLikeState'));
      expect(player, contains('_resolvedLikeState'));
      expect(player, isNot(contains('isLikeLoading: _isLikeActionLoading')));
      expect(player, contains('_isReportActionLoading'));
      expect(player, contains('_isDeleteActionLoading'));
      expect(player, contains('_isAddVideoActionLoading'));
      expect(player, contains('VideoActionRail('));
      expect(actionRail, contains('class VideoActionRail'));
      expect(actionRail, contains('VideoUiStrings.delete'));
      expect(actionRail, contains('VideoUiStrings.moreVideoActions'));
      expect(actionRail, contains('VideoUiStrings.reportVideoSemantic'));
      expect(actionRail, contains('VideoUiStrings.profile'));
      expect(actionRail, contains('_buildMoreAction'));
      expect(actionRail, contains('_VideoMoreActionTile'));
      expect(actionRail, contains('formatActionCount(video.likes.length)'));
      expect(actionRail, contains('formatActionCount(video.shareCount)'));
      expect(player, contains('_confirmReport'));
      expect(player, contains('_openAddVideo(videoController)'));
      expect(actionRail, contains('Semantics('));
      expect(actionRail, isNot(contains("label: '\${video.reportCount}'")));
    });

    test('video sensitive confirmations use a modern bottom sheet', () {
      final player = File(
        'lib/widgets/smart_video_player.dart',
      ).readAsStringSync();
      final playerSheets = File(
        'lib/widgets/smart_video_player_sheets.dart',
      ).readAsStringSync();
      final playerSurface = '$player\n$playerSheets';
      final videoStrings = File(
        'lib/utils/video_ui_strings.dart',
      ).readAsStringSync();

      expect(player, contains('showModalBottomSheet<void>'));
      expect(playerSurface, contains('_VideoActionConfirmationSheet'));
      expect(playerSurface, contains('DraggableScrollableSheet'));
      expect(playerSurface, contains('SafeArea('));
      expect(playerSurface, contains('FilledButton.icon'));
      expect(playerSurface, contains('OutlinedButton'));
      expect(player, contains('VideoUiStrings.deleteVideoSheetMessage'));
      expect(player, contains('VideoUiStrings.reportVideoSheetMessage'));
      expect(playerSurface, isNot(contains('AlertDialog(')));
      expect(playerSurface, isNot(contains('Get.dialog(')));
      expect(videoStrings, contains('deleteVideoPrimaryAction'));
      expect(videoStrings, contains('reportVideoPrimaryAction'));
      expect(videoStrings, contains('sensitiveActionWarning'));
    });

    test('video user-facing strings stay centralized', () {
      final controller = File(
        'lib/controller/video_controller.dart',
      ).readAsStringSync();
      final repository = File(
        'lib/services/videos/video_repository.dart',
      ).readAsStringSync();
      final videoFeed = File(
        'lib/screens/video_feed_screen.dart',
      ).readAsStringSync();
      final profileFeed = File(
        'lib/screens/profil_video_scrollview.dart',
      ).readAsStringSync();
      final tiktokPlayer = File(
        'lib/widgets/tiktok_video_player.dart',
      ).readAsStringSync();
      final videoStrings = File(
        'lib/utils/video_ui_strings.dart',
      ).readAsStringSync();

      expect(videoFeed, contains('VideoUiStrings.emptyVideoFeedTitle'));
      expect(videoFeed, contains('VideoUiStrings.emptyVideoFeedMessage'));
      expect(
        profileFeed,
        contains('VideoUiStrings.emptyProfileVideoFeedTitle'),
      );
      expect(
        profileFeed,
        contains('VideoUiStrings.emptyProfileVideoFeedMessage'),
      );
      expect(profileFeed, contains('VideoUiStrings.back'));
      expect(controller, contains('VideoUiStrings.likeOffline'));
      expect(controller, contains('VideoUiStrings.reportOffline'));
      expect(controller, contains('VideoUiStrings.deleteOffline'));
      expect(controller, contains('VideoUiStrings.shareOffline'));
      expect(repository, contains('VideoUiStrings.videoNotFound'));
      expect(repository, contains('VideoUiStrings.reportUnavailable'));
      expect(
        tiktokPlayer,
        contains('VideoUiStrings.forwardTenSecondsFeedback'),
      );
      expect(tiktokPlayer, contains('VideoUiStrings.rewindTenSecondsFeedback'));
      expect(videoStrings, contains('emptyVideoFeedTitle'));
      expect(videoStrings, contains('emptyHomeVideoFeedTitle'));
      expect(videoStrings, contains('noInternetMessage'));
      expect(videoStrings, contains('videoSearchUnavailable'));
      expect(videoStrings, contains('reportUnavailable'));
    });

    test('video feedback uses the branded professional surface', () {
      final feedback = File('lib/widgets/ad_feedback.dart').readAsStringSync();
      final toastWrappers = File(
        'lib/screens/success_toast.dart',
      ).readAsStringSync();
      final actionResponse = File(
        'lib/models/action_response.dart',
      ).readAsStringSync();

      expect(feedback, contains('OverlayEntry'));
      expect(feedback, contains('AdSystemNotice('));
      expect(feedback, contains('AdSystemNoticeData('));
      expect(feedback, contains('AdSystemNoticeTone.success'));
      expect(feedback, contains('AdSystemNoticeTone.info'));
      expect(feedback, contains('AdSystemNoticeTone.warning'));
      expect(feedback, contains('AdSystemNoticeTone.error'));
      expect(feedback, contains('Semantics('));
      expect(feedback, contains('liveRegion: true'));
      expect(feedback, isNot(contains('Get.showSnackbar')));
      expect(feedback, isNot(contains('GetSnackBar')));
      expect(feedback, isNot(contains('SnackStyle.FLOATING')));
      expect(feedback, isNot(contains('Get.snackbar(')));
      expect(toastWrappers, contains('Action confirmée'));
      expect(toastWrappers, contains('Action impossible'));
      expect(toastWrappers, contains('À noter'));
      expect(actionResponse, contains('Action réalisée.'));
      expect(actionResponse, contains('Réessaie quand tu es en ligne.'));
      expect(actionResponse, isNot(contains('Ã')));
    });

    test('video like flow falls back to narrow Firestore toggle', () {
      final controller = File(
        'lib/controller/video_controller.dart',
      ).readAsStringSync();
      final repository = File(
        'lib/services/videos/video_repository.dart',
      ).readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();

      expect(controller, contains("'likeVideo'"));
      expect(controller, contains('_likeVideoWithFirestoreFallback'));
      expect(controller, contains("response.code == 'unauthenticated'"));
      expect(repository, contains('FieldValue.arrayUnion([userId])'));
      expect(repository, contains('FieldValue.arrayRemove([userId])'));
      expect(rules, contains('function canToggleVideoLike()'));
      expect(rules, contains('function canAddVideoLike()'));
      expect(rules, contains('function canRemoveVideoLike()'));
      expect(rules, contains('changesOnly(["likes"])'));
      expect(rules, contains('allow update: if canToggleVideoLike();'));
    });

    test('video report flow keeps auth failures controlled', () {
      final controller = File(
        'lib/controller/video_controller.dart',
      ).readAsStringSync();
      final actionService = File(
        'lib/services/videos/video_action_service.dart',
      ).readAsStringSync();
      final rules = File('firestore.rules').readAsStringSync();

      expect(controller, contains("'reportVideo'"));
      expect(actionService, contains('callDataWithHttpFallback'));
      expect(controller, contains('_reportVideoWithFirestoreFallback'));
      expect(actionService, contains('isAuthAccessFailure'));
      expect(actionService, contains('authRequiredResponse'));
      expect(actionService, contains("code: 'unauthenticated'"));
      expect(controller, contains("response.code == 'unauthenticated'"));
      expect(
        controller,
        contains('response.success ? ToastLevel.success : response.toast'),
      );
      expect(
        controller,
        isNot(
          contains('response.success ? ToastLevel.success : ToastLevel.error'),
        ),
      );
      expect(rules, contains('function canReportVideo()'));
      expect(rules, contains('changesOnly(["reports", "reportCount"])'));
      expect(
        rules,
        contains('request.auth.uid in request.resource.data.reports'),
      );
      expect(rules, contains('allow update: if canReportVideo();'));
    });

    test(
      'video captions stay separated from the action rail on small screens',
      () {
        final player = File(
          'lib/widgets/smart_video_player.dart',
        ).readAsStringSync();
        final playerSheets = File(
          'lib/widgets/smart_video_player_sheets.dart',
        ).readAsStringSync();
        final playerSurface = '$player\n$playerSheets';
        final tiktokPlayer = File(
          'lib/widgets/tiktok_video_player.dart',
        ).readAsStringSync();
        final playbackControls = File(
          'lib/widgets/video_playback_controls.dart',
        ).readAsStringSync();
        final home = File('lib/screens/home_screen.dart').readAsStringSync();
        final profileFeed = File(
          'lib/screens/profil_video_scrollview.dart',
        ).readAsStringSync();

        expect(player, contains('_buildVideoReadabilityScrim()'));
        expect(player, isNot(contains('heightFactor: 0.46')));
        expect(player, isNot(contains('alpha: 0.74')));
        expect(player, contains('_buildVideoMetadataOverlay(context)'));
        expect(player, isNot(contains('_buildPublisherAvatar')));
        expect(player, isNot(contains('_publisherInitials')));
        expect(player, isNot(contains('_videoPublisherAvatarSize')));
        expect(player, contains('VideoActionRail.reservedWidth'));
        expect(player, contains('media.viewPadding.bottom'));
        expect(player, contains('maxLines: _captionCollapsedMaxLines'));
        expect(player, contains('_showCaptionSheet'));
        expect(playerSurface, contains('_VideoCaptionSheet'));
        expect(
          playerSurface,
          contains('VideoUiStrings.videoCaptionSheetTitle'),
        );
        expect(player, contains('VideoUiStrings.seeMore'));
        expect(playerSurface, contains('SingleChildScrollView'));
        expect(
          player,
          contains('VideoUiStrings.videoPublisherProfileSemantic'),
        );
        expect(
          File('lib/widgets/video_action_rail.dart').readAsStringSync(),
          contains('static const double buttonExtent = 48'),
        );
        expect(
          tiktokPlayer,
          contains('bottom: _progressBottomOffset(context)'),
        );
        expect(playbackControls, contains('AdColors.brand'));
        expect(tiktokPlayer, contains('viewPadding.bottom'));

        expect(home, isNot(contains('FadeTransition')));
        expect(home, contains('_buildVideoSearchLauncher'));
        expect(home, contains('_VideoSearchSheet'));
        expect(home, contains('_openVideoSearchSheet'));
        expect(home, contains('VideoUiStrings.videoSearchTitle'));
        expect(profileFeed, isNot(contains('bottom: 100')));
      },
    );

    test('video runtime keeps MP4 as the only playback path', () {
      final player = File(
        'lib/widgets/smart_video_player.dart',
      ).readAsStringSync();
      final manager = File('lib/widgets/video_manager.dart').readAsStringSync();
      final orchestrator = File(
        'lib/videos/domain/video_focus_orchestrator.dart',
      ).readAsStringSync();
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      final videoFeed = File(
        'lib/screens/video_feed_screen.dart',
      ).readAsStringSync();
      final profileScroll = File(
        'lib/screens/profil_video_scrollview.dart',
      ).readAsStringSync();

      expect(manager, contains('bool adaptiveSourcesEnabled = false;'));
      expect(manager, isNot(contains('VideoFormat.')));
      expect(orchestrator, isNot(contains('alternatePlaybackForVideo')));
      expect(player, isNot(contains('alternatePlaybackRequested')));
      expect(player, isNot(contains('_forceMp4Fallback')));
      expect(home, isNot(contains('alternatePlaybackForVideo')));
      expect(videoFeed, isNot(contains('alternatePlaybackForVideo')));
      expect(profileScroll, isNot(contains('alternatePlaybackForVideo')));
    });

    test(
      'video preload keeps active playback first and staggers cache work',
      () {
        final manager = File(
          'lib/widgets/video_manager.dart',
        ).readAsStringSync();
        final orchestrator = File(
          'lib/videos/domain/video_focus_orchestrator.dart',
        ).readAsStringSync();

        expect(orchestrator, contains('await videoManager.pauseAllExcept'));
        expect(orchestrator, contains('videoManager.preloadSurrounding'));
        expect(manager, contains('_preloadRequestTokensByContext'));
        expect(manager, contains('_secondaryPreloadDelay'));
        expect(manager, contains('_preloadVideoAfterDelay'));
        expect(manager, contains('preloadPositionDelayForTests'));
        expect(manager, contains('preloadRadius: 2'));
        expect(manager, contains('preloadRadius: 3'));
      },
    );

    test(
      'video production observability covers playback actions and upload',
      () {
        final smartPlayer = File(
          'lib/widgets/smart_video_player.dart',
        ).readAsStringSync();
        final videoController = File(
          'lib/controller/video_controller.dart',
        ).readAsStringSync();
        final uploadController = File(
          'lib/controller/upload_video_controller.dart',
        ).readAsStringSync();
        final observability = File(
          'lib/services/video_observability_service.dart',
        ).readAsStringSync();

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
      },
    );

    test('video playback failures keep a clear retry state', () {
      final smartPlayer = File(
        'lib/widgets/smart_video_player.dart',
      ).readAsStringSync();
      final tiktokPlayer = File(
        'lib/widgets/tiktok_video_player.dart',
      ).readAsStringSync();
      final stateOverlay = File(
        'lib/widgets/video_state_overlay.dart',
      ).readAsStringSync();
      final playbackControls = File(
        'lib/widgets/video_playback_controls.dart',
      ).readAsStringSync();
      final videoStrings = File(
        'lib/utils/video_ui_strings.dart',
      ).readAsStringSync();

      expect(smartPlayer, contains("reason: 'runtime_value_error'"));
      expect(smartPlayer, contains('VideoUiStrings.playbackInterruptedRetry'));
      expect(tiktokPlayer, contains('Widget _buildSafeState'));
      expect(tiktokPlayer, contains('_buildPosterReadabilityScrim'));
      expect(tiktokPlayer, contains('VideoStateOverlay.loading'));
      expect(tiktokPlayer, contains('VideoStateOverlay.error'));
      expect(stateOverlay, contains('VideoUiStrings.loadingMessage'));
      expect(stateOverlay, contains('VideoUiStrings.slowLoadingDetail'));
      expect(stateOverlay, contains('_publicErrorMessage'));
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
    test(
      'visible video binds a newly ready managed controller without scroll',
      () {
        final smartPlayer = File(
          'lib/widgets/smart_video_player.dart',
        ).readAsStringSync();

        expect(smartPlayer, contains('shouldBindManagedPlayer'));
        expect(
          smartPlayer,
          contains(
            'managedPlayer != null && !identical(managedPlayer, _player)',
          ),
        );
        expect(smartPlayer, contains('_bindPlayer(managedPlayer);'));
        expect(smartPlayer, contains('_scheduleMaybePlay();'));
      },
    );

    test('home video search stays separate from the live feed state', () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      final repository = File(
        'lib/services/home/home_feed_repository.dart',
      ).readAsStringSync();

      expect(
        home,
        contains('List<Video> get _currentVideos => _isSearchActive'),
      );
      expect(home, contains('_searchResults.toList(growable: false)'));
      expect(
        home,
        contains('videoController.videoList.toList(growable: false)'),
      );
      expect(home, contains('if (_isSearchActive) {'));
      expect(home, contains('return;'));
      expect(home, contains('_feedIndexBeforeSearch'));
      expect(home, contains('_jumpToPageSilently(restoreIndex)'));
      expect(home, contains('fetchReadyVideosForAuthors'));
      expect(repository, contains('whereIn: ids'));
      expect(home, contains('_isSearchSheetOpen'));
    });

    test('home pending live videos use a clear non-overlapping chip', () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      final videoStrings = File(
        'lib/utils/video_ui_strings.dart',
      ).readAsStringSync();

      expect(home, contains('_buildPendingLiveVideosChip'));
      expect(home, contains('VideoUiStrings.pendingVideosLabel(pending)'));
      expect(home, contains('VideoUiStrings.pendingVideosSemantic(pending)'));
      expect(home, contains('top: kToolbarHeight + 10'));
      expect(home, contains('_isSearchSheetOpen'));
      expect(home, contains('HapticFeedback.lightImpact'));
      expect(home, isNot(contains("pending > 1 ? '\$pending nouvelles")));
      expect(videoStrings, contains('pendingVideosLabel'));
      expect(videoStrings, contains('pendingVideosSemantic'));
      expect(videoStrings, contains('pendingVideosAction'));
    });

    test('home route refresh focuses uploaded video before autoplay', () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      final repository = File(
        'lib/services/home/home_feed_repository.dart',
      ).readAsStringSync();

      expect(home, contains('_captureRoutePlaybackRequest'));
      expect(home, contains("_routeFocusVideoId = rawVideoId.trim();"));
      expect(home, contains('_ensureFocusedVideoVisible'));
      expect(home, contains('focusVideoId: _routeFocusVideoId'));
      expect(home, contains('fetchReadyVideoById('));
      expect(home, contains('targetId'));
      expect(repository, contains('Video.fromDoc(doc)'));
      expect(home, contains('_activateHomeIndex(targetIndex'));
    });

    test('home activates a live-ready video after an empty feed', () {
      final controller = File(
        'lib/controller/video_controller.dart',
      ).readAsStringSync();
      final home = File('lib/screens/home_screen.dart').readAsStringSync();

      expect(controller, contains('currentIndex.value < 0'));
      expect(controller, contains('currentIndex.value = 0;'));
      expect(home, contains('_wasHomeFeedEmpty'));
      expect(home, contains('_scheduleHomeFeedActivationAfterEmptyFeed'));
      expect(home, contains('unawaited(_onPageChanged(safeIndex));'));
    });

    test(
      'home profile action uses a professional generated avatar fallback',
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
      },
    );
  });
}
