import 'package:get/get.dart';

class VideoUiStrings {
  VideoUiStrings._();

  static String get loadingMessage => 'loadingMessage'.tr;
  static String get slowLoadingMessage => 'slowLoadingMessage'.tr;
  static String get slowLoadingDetail => 'slowLoadingDetail'.tr;
  static String get playbackErrorTitle => 'playbackErrorTitle'.tr;
  static String get playbackUnavailable => 'playbackUnavailable'.tr;
  static String get playbackInterruptedRetry => 'playbackInterruptedRetry'.tr;
  static String get retry => 'retry'.tr;
  static String get play => 'play'.tr;
  static String get pause => 'pause'.tr;
  static String get playVideo => 'playVideo'.tr;
  static String get pauseVideo => 'pauseVideo'.tr;
  static String get rewindTenSeconds => 'rewindTenSeconds'.tr;
  static String get forwardTenSeconds => 'forwardTenSeconds'.tr;
  static String get rewindTenSecondsFeedback => 'rewindTenSecondsFeedback'.tr;
  static String get forwardTenSecondsFeedback => 'forwardTenSecondsFeedback'.tr;
  static String get playbackSpeed => 'playbackSpeed'.tr;
  static String get currentPlaybackSpeed => 'currentPlaybackSpeed'.tr;
  static String get progressBarSemantic => 'progressBarSemantic'.tr;

  static String get loadingTooLong => 'loadingTooLong'.tr;
  static String get playbackError => 'playbackError'.tr;
  static String get actionTimedOut => 'actionTimedOut'.tr;
  static String get genericActionImpossible => 'genericActionImpossible'.tr;
  static String get genericActionRetry => 'genericActionRetry'.tr;
  static String get defaultPublisherName => 'defaultPublisherName'.tr;
  // `seeMoreCaption` / `seeLessCaption` / `seeLess` have no callers anywhere
  // in the app -- `seeMore` alone is used, for a link that always opens the
  // caption sheet rather than expanding in place. Left as plain literals:
  // nothing renders them, so there is nothing to translate.
  static const String seeMoreCaption = 'Voir plus la légende';
  static const String seeLessCaption = 'Voir moins la légende';
  static String get seeMore => 'seeMore'.tr;
  static const String seeLess = 'Voir moins';
  static String get videoCaptionSheetTitle => 'videoCaptionSheetTitle'.tr;
  static String get videoCaptionOpen => 'videoCaptionOpen'.tr;
  static String get videoPublisherProfileSemantic =>
      'videoPublisherProfileSemantic'.tr;
  static String get back => 'back'.tr;
  // `emptyVideoFeedTitle` / `emptyVideoFeedMessage` sont partis avec
  // `video_feed_screen.dart`, leur seul lecteur : un troisième feed vidéo
  // qu'aucun écran n'ouvrait plus. Les deux feeds qui restent ont leur propre
  // formulation, `emptyProfileVideoFeed*` et `emptyHomeVideoFeed*`, parce que
  // « aucune vidéo » ne se dit pas pareil sur un profil et sur l'accueil.
  static String get emptyProfileVideoFeedTitle =>
      'emptyProfileVideoFeedTitle'.tr;
  static String get emptyProfileVideoFeedMessage =>
      'emptyProfileVideoFeedMessage'.tr;
  static String get emptyHomeVideoFeedTitle => 'emptyHomeVideoFeedTitle'.tr;
  static String get emptyHomeVideoFeedPlayerMessage =>
      'emptyHomeVideoFeedPlayerMessage'.tr;
  static String get emptyHomeVideoFeedDefaultMessage =>
      'emptyHomeVideoFeedDefaultMessage'.tr;
  static String get noInternetTitle => 'noInternetTitle'.tr;
  static String get noInternetMessage => 'noInternetMessage'.tr;
  static String get refresh => 'refresh'.tr;

  // `delete` / `deleteVideoConfirm` / `cancel` / `report` / `reported` /
  // `reportVideoModeration` / `addVideo` have no callers anywhere in the app
  // -- superseded by the more specific members below (`deleteVideoSemantic`,
  // `reportVideoSemantic`/`reportedVideoSemantic`, `addVideoSemantic`, etc.).
  // Left as plain literals: nothing renders them, so there is nothing to
  // translate. `addVideo` is still asserted verbatim by
  // video_ui_strings_test.dart, which is fine either way.
  static const String delete = 'Supprimer';
  static String get deleteVideoTitle => 'deleteVideoTitle'.tr;
  static const String deleteVideoConfirm = 'Confirmer la suppression ?';
  static String get deleteVideoSheetMessage => 'deleteVideoSheetMessage'.tr;
  static String get deleteVideoPrimaryAction => 'deleteVideoPrimaryAction'.tr;
  static String get deleteVideoSemantic => 'deleteVideoSemantic'.tr;
  static const String cancel = 'Annuler';

  static String get likeVideo => 'likeVideo'.tr;
  static String get unlikeVideo => 'unlikeVideo'.tr;
  static String get shareVideo => 'shareVideo'.tr;
  static const String report = 'Signaler';
  static const String reported = 'Signalé';
  static String get reportVideoTitle => 'reportVideoTitle'.tr;
  static String get reportVideoSemantic => 'reportVideoSemantic'.tr;
  static String get reportedVideoSemantic => 'reportedVideoSemantic'.tr;
  static const String reportVideoModeration =
      'Ce signalement sera transmis à la modération.';
  static String get reportVideoSheetMessage => 'reportVideoSheetMessage'.tr;
  static String get reportVideoPrimaryAction => 'reportVideoPrimaryAction'.tr;
  static String get sensitiveActionWarning => 'sensitiveActionWarning'.tr;
  static String get moderationReviewLabel => 'moderationReviewLabel'.tr;
  static String get moreVideoActions => 'moreVideoActions'.tr;
  static String get moreVideoActionsSemantic => 'moreVideoActionsSemantic'.tr;
  static const String addVideo = 'Ajouter';
  static String get addVideoSemantic => 'addVideoSemantic'.tr;
  static String get profile => 'profile'.tr;
  static String get openProfile => 'openProfile'.tr;
  static String get followProfile => 'followProfile'.tr;
  static String get followingProfile => 'followingProfile'.tr;
  static String get ownProfile => 'ownProfile'.tr;
  static String get followUnavailable => 'followUnavailable'.tr;
  static String get protectedAccessTitle => 'protectedAccessTitle'.tr;
  static String get protectedAccessMessage => 'protectedAccessMessage'.tr;
  static String get sessionRevokedMessage => 'sessionRevokedMessage'.tr;
  static String get authRequiredMessage => 'authRequiredMessage'.tr;

  static String get missingShareUrl => 'missingShareUrl'.tr;
  // Developer-facing (fed to the telemetry `message:` field), never shown to
  // a user -- deliberately left untranslated, unlike `missingShareUrl` right
  // above it which is the actual on-screen toast for the same failure.
  static const String missingShareUrlLog =
      'Lien video indisponible pour le partage.';
  static String get shareUnavailable => 'shareUnavailable'.tr;
  static String get shareOffline => 'shareOffline'.tr;
  static String get shareRecorded => 'shareRecorded'.tr;
  static String get shareTitle => 'shareTitle'.tr;
  static String get shareSubject => 'shareSubject'.tr;
  static String get shareEmptyCaption => 'shareEmptyCaption'.tr;
  static String get shareWithCaptionPrefix => 'shareWithCaptionPrefix'.tr;
  static String get likeOffline => 'likeOffline'.tr;
  static String get likeAdded => 'likeAdded'.tr;
  static String get likeRemoved => 'likeRemoved'.tr;
  static String get likeUnavailable => 'likeUnavailable'.tr;
  static String get reportOffline => 'reportOffline'.tr;
  static String get videoNotFound => 'videoNotFound'.tr;
  static String get videoAlreadyReported => 'videoAlreadyReported'.tr;
  static String get reportSent => 'reportSent'.tr;
  static String get reportUnavailable => 'reportUnavailable'.tr;
  static String get deleteOffline => 'deleteOffline'.tr;

  static String get videoSearchOpen => 'videoSearchOpen'.tr;
  static String get videoSearchIdleLabel => 'videoSearchIdleLabel'.tr;
  static String get videoSearchTitle => 'videoSearchTitle'.tr;
  static String get videoSearchHint => 'videoSearchHint'.tr;
  static String get videoSearchClear => 'videoSearchClear'.tr;
  static String get videoSearchLoadingTitle => 'videoSearchLoadingTitle'.tr;
  static String get videoSearchLoadingMessage => 'videoSearchLoadingMessage'.tr;
  static String get videoSearchEmptyTitle => 'videoSearchEmptyTitle'.tr;
  static String get videoSearchEmptyMessage => 'videoSearchEmptyMessage'.tr;
  static String get videoSearchUnavailable => 'videoSearchUnavailable'.tr;
  static const String videoSearchResultsTitle = 'Résultats';
  static String get videoSearchResultHint => 'videoSearchResultHint'.tr;
  static String get pendingVideosAction => 'pendingVideosAction'.tr;

  /* --------------------------- Fin du fil vidéo --------------------------- */

  static String get feedEndTitle => 'feedEndTitle'.tr;

  static String feedEndMessage(int count) {
    return count > 1
        ? 'feedEndMessagePlural'.trParams({'count': '$count'})
        : 'feedEndMessageSingular'.tr;
  }

  static String get feedEndRefreshAction => 'feedEndRefreshAction'.tr;
  static String get feedEndSearchAction => 'feedEndSearchAction'.tr;

  static String pendingVideosLabel(int count) {
    return count > 1
        ? 'pendingVideosLabelPlural'.trParams({'count': '$count'})
        : 'pendingVideosLabelSingular'.tr;
  }

  static String pendingVideosSemantic(int count) {
    return count > 1
        ? 'pendingVideosSemanticPlural'.trParams({'count': '$count'})
        : 'pendingVideosSemanticSingular'.tr;
  }

  static const String uploadMissingRequiredFields =
      'Merci de renseigner une description et une légende.';
  static const String uploadSourceNotFound =
      'Vidéo introuvable. Merci de réessayer.';
  static const String uploadEmptyFile = 'Le fichier vidéo est vide.';
  static const String uploadFileTooLarge =
      'Le fichier vidéo dépasse la limite de 150 Mo.';
  static const String uploadQualityTooLow =
      'Qualité vidéo insuffisante (minimum 480x360).';
  static const String uploadThumbnailFailed =
      'Erreur lors de la génération de la miniature.';
  static const String uploadPreparationFailed =
      'Préparation impossible pour le moment. Merci de réessayer.';
  static const String uploadPreparationInProgress = 'Préparation en cours...';
  static const String uploadAlreadyInProgress = 'Téléversement déjà en cours.';
  static const String uploadMissingFile = 'Fichier manquant.';
  static const String uploadMissingThumbnail = 'Miniature manquante.';
  static const String uploadMissingMetadata =
      'Description ou légende manquante.';
  static const String uploadVideoTransferFailed =
      'Échec du téléversement de la vidéo.';
  static const String uploadThumbnailTransferFailed =
      'Échec du téléversement de la miniature.';
  static const String uploadFinalizeFailed =
      'Échec de la finalisation serveur.';
  static const String uploadCancelled = 'Téléversement annulé.';
  static const String uploadPreparationCancelled = 'Préparation annulée.';
  static const String uploadSuccess = 'Vidéo prête et visible.';
  static const String uploadSubmittedForReview =
      'Vidéo soumise à la revue admin. Retrouvez-la dans votre profil ; '
      'vous serez notifié dès sa validation.';
  // Shown when the app stops waiting before the backend has finished, not
  // when anything failed. It must send the user somewhere concrete, because
  // the alternative — "it's processing", full stop — is what made a
  // successful upload feel like a lost video.
  static const String uploadOptimizationPending =
      'Votre vidéo est en cours de traitement. Suivez son avancement '
      'dans votre profil ; vous serez notifié dès sa validation.';

  /* ------------------------ Plafond de publication ------------------------- */

  // Le message serveur, « Vous avez deja 10 videos publiques. Archivez une
  // video avant d'en ajouter une nouvelle. », remontait tel quel à l'écran.
  // Il est sans accents, et surtout il demande une action qu'un joueur ne
  // peut pas faire : archiver n'existe pas dans l'application. La seule issue
  // réelle est de faire relever le plafond par l'agence, donc c'est ce que le
  // message doit dire.
  static String get uploadQuotaReachedTitle => 'uploadQuotaReachedTitle'.tr;

  static String uploadQuotaReachedMessage(int limit) =>
      'uploadQuotaReachedMessage'.trParams({'limit': '$limit'});

  static String uploadQuotaReachedShort(int limit) =>
      'Plafond de $limit vidéos atteint. Contactez l’agence Adfoot pour '
      'l’augmenter.';

  static String get uploadQuotaContactAction => 'uploadQuotaContactAction'.tr;
  static String get uploadQuotaDismissAction => 'uploadQuotaDismissAction'.tr;

  static String uploadQuotaContactFallback(String phone, String website) =>
      'uploadQuotaContactFallback'.trParams({
        'phone': phone,
        'website': website,
      });

  /* ------------------------------ Cycle de vie ----------------------------- */

  static const String videoStateProcessing = 'Traitement…';
  static const String videoStateUnderReview = 'En validation';
  static const String videoStateModerated = 'Retirée';
  static const String videoStateFailed = 'Échec';
  static const String videoNotPlayableProcessing =
      'Cette vidéo est encore en cours de traitement.';
  static const String videoNotPlayableUnderReview =
      'Cette vidéo attend la validation d’un administrateur. '
      'Vous serez notifié dès qu’elle sera visible.';
  // Deliberately does not promise a notification: the decision has already
  // been taken, so there is nothing left to wait for.
  static const String videoNotPlayableModerated =
      'Cette vidéo a été retirée du public par la modération. '
      'Contactez le support si vous pensez qu’il s’agit d’une erreur.';
  static const String videoNotPlayableFailed =
      'Le traitement de cette vidéo a échoué. Supprimez-la et réessayez.';
  static const String uploadAuthRequired =
      'Authentification requise. Reconnectez-vous puis réessayez.';
  static const String uploadPermissionDenied =
      'Votre compte ne peut pas téléverser de vidéos.';
  static const String uploadServiceUnavailable =
      'Le service vidéo est temporairement indisponible.';
  static const String uploadPreconditionFailed =
      'Votre compte ne remplit pas les conditions pour téléverser.';
  static const String uploadProfileLoadFailed =
      'Impossible de charger le profil. Vérifiez votre réseau puis réessayez.';
  static const String uploadServerError =
      'Erreur serveur pendant le téléversement.';
  static const String uploadConnectionUnstable =
      'Connexion instable pendant le téléversement. Vérifiez votre réseau '
      'puis réessayez.';
  static const String uploadSessionTimeout =
      'Connexion sécurisée trop longue à s’établir. '
      'Vérifiez votre réseau puis réessayez.';
  static const String uploadUnknownError = 'Erreur pendant le téléversement.';
  static const String uploadStageAnalyze = 'Analyse de la vidéo...';
  static const String uploadStagePrepareFile = 'Préparation du fichier...';
  static const String uploadStageGenerateThumbnail =
      'Génération de la miniature...';
  static const String uploadStageLoadProfile = 'Vérification du profil...';
  static const String uploadStageInitialize = 'Initialisation...';
  static const String uploadStageUploading = 'Téléversement...';
  static const String uploadStageRefreshSecureLink =
      'Renouvellement du lien sécurisé...';
  static const String uploadStagePrepareSecureThumbnail =
      'Préparation miniature sécurisée...';
  static const String uploadStageSendThumbnail = 'Envoi de la miniature...';
  static const String uploadStageFinalize = 'Finalisation...';
  static String get uploadOptimizationTitle => 'uploadOptimizationTitle'.tr;
  static String get uploadProgressTitle => 'uploadProgressTitle'.tr;
  static String get uploadPreparationTitle => 'uploadPreparationTitle'.tr;
  static String get uploadProgressSubtitle => 'uploadProgressSubtitle'.tr;
  static String get uploadPreparationSubtitle => 'uploadPreparationSubtitle'.tr;
  static String get uploadOptimizationSubtitle =>
      'uploadOptimizationSubtitle'.tr;
  static const String uploadProgressLabel = 'Progression';
  static const String uploadCurrentStepLabel = 'Étape actuelle';
  static String get uploadCancelAction => 'uploadCancelAction'.tr;
  static String get discardDraftTitle => 'discardDraftTitle'.tr;
  static String get discardDraftMessage => 'discardDraftMessage'.tr;
  static String get discardDraftConfirm => 'discardDraftConfirm'.tr;
  static String get discardDraftCancel => 'discardDraftCancel'.tr;
  static const String uploadStepPrepare = 'Préparation';
  static const String uploadStepTransfer = 'Transfert';
  static const String uploadStepThumbnail = 'Miniature';
  static const String uploadStepFinalize = 'Finalisation';
  static const String uploadStageOptimize = 'Optimisation en cours...';
  static const String uploadStagePreparing = 'Préparation...';
  static const String uploadStageCompressing = 'Compression...';
  static const String uploadStageUploadingVideo = 'Téléversement vidéo...';
  static const String uploadStageUploadingThumbnail =
      'Téléversement miniature...';
  static String get addVideoScreenTitle => 'addVideoScreenTitle'.tr;
  static String get addVideoScreenSubtitle => 'addVideoScreenSubtitle'.tr;
  static String get uploadFormTitle => 'uploadFormTitle'.tr;
  static String get uploadFormSubtitle => 'uploadFormSubtitle'.tr;
  static String get noVideoSelected => 'noVideoSelected'.tr;
  static String get galleryPermissionTitle => 'galleryPermissionTitle'.tr;
  static String get galleryPermissionMessage => 'galleryPermissionMessage'.tr;
  static String get videoSelectionErrorTitle => 'videoSelectionErrorTitle'.tr;
  static String get uploadUnexpectedErrorTitle =>
      'uploadUnexpectedErrorTitle'.tr;
  static String get addVideoPickTitle => 'addVideoPickTitle'.tr;
  static String get uploadConstraintsHint => 'uploadConstraintsHint'.tr;
  static String get chooseFromGallery => 'chooseFromGallery'.tr;
  static String get maxDurationChip => 'maxDurationChip'.tr;
  static String get minQualityChip => 'minQualityChip'.tr;
  static String get maxFileSizeChip => 'maxFileSizeChip'.tr;
  static String get autoOptimizationChip => 'autoOptimizationChip'.tr;
  static String get overlayLoading => 'overlayLoading'.tr;
  static const String overlayUploading = 'Téléversement en cours';
  static String get overlayWaiting => 'overlayWaiting'.tr;
  static String get descriptionLabel => 'descriptionLabel'.tr;
  static String get descriptionHint => 'descriptionHint'.tr;
  static String get descriptionRequired => 'descriptionRequired'.tr;
  static String get minThreeChars => 'minThreeChars'.tr;
  static String get captionLabel => 'captionLabel'.tr;
  static String get captionHint => 'captionHint'.tr;
  static String get captionRequired => 'captionRequired'.tr;
  static String get uploadVideoButton => 'uploadVideoButton'.tr;
  static String get uploadReminder => 'uploadReminder'.tr;

  static String buildShareText({
    required String shareUrl,
    required String caption,
  }) {
    final trimmedCaption = caption.trim();
    if (trimmedCaption.isEmpty) {
      return '$shareEmptyCaption\n$shareUrl';
    }

    final shortCaption = trimmedCaption.length > 120
        ? '${trimmedCaption.substring(0, 117).trim()}...'
        : trimmedCaption;
    return '$shareWithCaptionPrefix $shortCaption\n$shareUrl';
  }

  static String formatPlaybackTime(Duration duration) {
    final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds ~/ 60).remainder(60);
    final seconds = totalSeconds.remainder(60);
    final paddedMinutes = minutes.toString().padLeft(2, '0');
    final paddedSeconds = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$paddedMinutes:$paddedSeconds';
    }
    return '$paddedMinutes:$paddedSeconds';
  }

  static String playbackProgressValue(Duration current, Duration total) {
    return '${formatPlaybackTime(current)} sur ${formatPlaybackTime(total)}';
  }

  static String likeCountValue(int count) {
    return count == 1 ? '1 mention J’aime' : '$count mentions J’aime';
  }

  static String shareCountValue(int count) {
    return count == 1 ? '1 partage' : '$count partages';
  }

  static String formatPlaybackSpeed(double speed) {
    final fixed = speed.toStringAsFixed(2);
    final trimmedZeros = fixed.replaceFirst(RegExp(r'0+$'), '');
    final normalized = trimmedZeros.endsWith('.')
        ? trimmedZeros.substring(0, trimmedZeros.length - 1)
        : trimmedZeros;
    return '${normalized}x';
  }

  static String selectPlaybackSpeed(double speed) {
    return 'Choisir la vitesse ${formatPlaybackSpeed(speed)}';
  }

  static String uploadTrimmed(int seconds) {
    return 'Vidéo préparée en extrait de ${seconds}s.';
  }

  static String uploadOptimizationFailed(String status) {
    return 'Échec d’optimisation vidéo (statut : $status). '
        'Merci de réessayer.';
  }

  static String galleryPermissionDetails(Object error) {
    return '$galleryPermissionMessage\n($error)';
  }

  static String videoSelectionFailed(Object error) {
    return 'videoSelectionFailed'.trParams({'error': '$error'});
  }

  static String unexpectedUploadError(Object error) {
    return 'unexpectedUploadError'.trParams({'error': '$error'});
  }
}
