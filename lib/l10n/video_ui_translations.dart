import 'package:get/get.dart';

/// GetX translations for context-free string catalogs: [VideoUiStrings]
/// [videoUiStringsRef] and any other plain static-string helper called from
/// controllers/services with no `BuildContext` at all -- `success_toast.dart`
/// so far too.
///
/// A second translation mechanism next to the ARB-based `AppLocalizations`
/// used for screens, needed exactly because those callers have no context to
/// resolve `AppLocalizations.of(context)` with. GetX's `.tr` extension
/// resolves from `Get.locale`/`Get.translations` globally, without a context
/// -- already available in this app via `GetMaterialApp`.
///
/// [videoUiStringsRef]: ../utils/video_ui_strings.dart
///
/// Keys are added incrementally as call sites are migrated screen by screen
/// (only the ones `home_screen.dart` and `success_toast.dart` use so far),
/// not all ~180 `VideoUiStrings` members at once -- see
/// [[project_adfoot_i18n_ios_effort]] in project memory.
class VideoUiTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {'fr': _fr, 'en': _en};

  static const Map<String, String> _fr = {
    'videoSearchOpen': 'Rechercher',
    'videoSearchIdleLabel': 'Poste, joueur, club',
    'videoSearchTitle': 'Recherche vidéo',
    'videoSearchHint': 'Poste, joueur, club...',
    'videoSearchClear': 'Effacer',
    'videoSearchResultHint': 'Ouvrir cette vidéo',
    'defaultPublisherName': 'Profil Adfoot',
    'videoSearchLoadingTitle': 'Recherche en cours',
    'videoSearchLoadingMessage': 'Nous cherchons les vidéos correspondantes.',
    'videoSearchEmptyTitle': 'Aucune vidéo trouvée',
    'videoSearchEmptyMessage':
        'Essayez avec attaquant, défenseur, milieu, gardien ou un autre poste.',
    'videoSearchUnavailable':
        'Recherche indisponible pour le moment. Réessayez dans un instant.',
    'pendingVideosAction': 'Voir',
    'pendingVideosLabelSingular': '1 nouvelle vidéo',
    'pendingVideosLabelPlural': '@count nouvelles vidéos',
    'pendingVideosSemanticSingular': '1 nouvelle vidéo disponible',
    'pendingVideosSemanticPlural': '@count nouvelles vidéos disponibles',
    'emptyHomeVideoFeedTitle': 'Aucune vidéo disponible',
    'emptyHomeVideoFeedPlayerMessage':
        'Soumettez votre première vidéo pour la proposer au feed.',
    'emptyHomeVideoFeedDefaultMessage':
        'Revenez plus tard ou actualisez le feed.',
    'addVideoSemantic': 'Soumettre une vidéo',
    'refresh': 'Actualiser',
    'noInternetTitle': 'Pas de connexion Internet',
    'noInternetMessage':
        'Vérifiez votre réseau, puis relancez le chargement du feed.',
    'retry': 'Réessayer',
    'actionConfirmedTitle': 'Action confirmée',
    'actionImpossibleTitle': 'Action impossible',
    'noteTitle': 'À noter',
    'emptyProfileVideoFeedTitle': 'Aucune vidéo à afficher',
    'emptyProfileVideoFeedMessage':
        'Ce profil n’a pas encore de vidéo disponible.',
    'back': 'Retour',
    'uploadFormTitle': 'Soumettre une vidéo',
    'uploadFormSubtitle': 'Prévisualisation et détails',
    'descriptionLabel': 'Description (obligatoire)',
    'descriptionHint': 'Ex: Dribble + frappe pied gauche',
    'descriptionRequired': 'La description est requise.',
    'minThreeChars': 'Au moins 3 caractères.',
    'captionLabel': 'Légende (obligatoire)',
    'captionHint': 'Ex: #U17 #Ailier #Vitesse',
    'captionRequired': 'La légende est requise.',
    'uploadVideoButton': 'Soumettre la vidéo',
    'uploadReminder':
        'Rappel : durée max 3 min • fichier max 150 Mo • '
        'validation admin avant publication',
    'discardDraftTitle': 'Abandonner cette vidéo ?',
    'discardDraftMessage':
        'Votre description et votre légende ne seront pas enregistrées.',
    'discardDraftConfirm': 'Abandonner',
    'discardDraftCancel': 'Continuer',
    'uploadUnexpectedErrorTitle': 'Erreur inattendue',
    'unexpectedUploadError': 'Erreur inattendue : @error',
    'uploadQuotaReachedTitle': 'Plafond de vidéos atteint',
    'uploadQuotaReachedMessage':
        'Votre compte a atteint son plafond de @limit vidéos publiées. '
        'Pour en publier davantage, demandez à l’agence Adfoot d’augmenter '
        'votre plafond.',
    'uploadQuotaContactAction': 'Contacter l’agence Adfoot',
    'uploadQuotaDismissAction': 'Fermer',
    'uploadQuotaContactFallback':
        'Écrivez à l’agence Adfoot sur WhatsApp au @phone, ou passez par '
        '@website, pour faire augmenter votre plafond de vidéos.',
    'uploadOptimizationTitle': 'Optimisation en cours',
    'uploadProgressTitle': 'Soumission en cours',
    'uploadPreparationTitle': 'Préparation de la vidéo',
    'uploadProgressSubtitle':
        'Garde l’application ouverte pendant le transfert.',
    'uploadPreparationSubtitle':
        'Nous préparons le fichier et la miniature avant l’envoi.',
    'uploadOptimizationSubtitle':
        'Nous finalisons la lecture et la qualité avant la revue admin.',
    'uploadCancelAction': 'Annuler le téléversement',
    'addVideoScreenTitle': 'Ajouter une vidéo',
    'addVideoScreenSubtitle': 'Soumission vidéo',
    'noVideoSelected': 'Aucune vidéo sélectionnée.',
    'galleryPermissionTitle': 'Autorisation requise',
    'galleryPermissionMessage':
        'Veuillez autoriser l’accès à la galerie pour '
        'sélectionner une vidéo.',
    'videoSelectionErrorTitle': 'Sélection impossible',
    'videoSelectionFailed': 'Échec lors de la sélection : @error',
    'addVideoPickTitle': 'Sélectionnez une vidéo à soumettre',
    'uploadConstraintsHint':
        'Durée max 3 min • Fichier max 150 Mo • Qualité minimale 480×360',
    'chooseFromGallery': 'Choisir depuis la galerie',
    'maxDurationChip': '≤ 3 minutes',
    'minQualityChip': '≥ 480×360',
    'maxFileSizeChip': '≤ 150 Mo',
    'autoOptimizationChip': 'Validation admin',
    'overlayLoading': 'Chargement...',
    'overlayWaiting': 'Veuillez patienter...',

    'loadingMessage': 'Chargement de la vidéo...',
    'slowLoadingMessage': 'Connexion lente...',
    'slowLoadingDetail':
        'La vidéo continue de charger. Réessayez si elle reste bloquée.',
    'playbackErrorTitle': 'Lecture impossible',
    'playbackUnavailable': 'Lecture vidéo indisponible.',
    'playbackInterruptedRetry': 'Lecture interrompue. Réessayez.',
    'play': 'Lecture',
    'pause': 'Pause',
    'playVideo': 'Lancer la vidéo',
    'pauseVideo': 'Mettre la vidéo en pause',
    'rewindTenSeconds': 'Reculer de 10 secondes',
    'forwardTenSeconds': 'Avancer de 10 secondes',
    'rewindTenSecondsFeedback': '-10s',
    'forwardTenSecondsFeedback': '+10s',
    'playbackSpeed': 'Vitesse de lecture',
    'currentPlaybackSpeed': 'Vitesse actuelle',
    'progressBarSemantic': 'Progression de la vidéo',
    'loadingTooLong': 'Le chargement prend trop de temps. Réessayez.',
    'playbackError': 'Erreur de lecture',
    'actionTimedOut':
        'Le serveur met trop de temps à répondre. Vérifiez votre réseau '
        'puis réessayez.',
    'genericActionImpossible': 'Action impossible.',
    'genericActionRetry': 'Action impossible pour le moment.',
    'seeMore': 'Voir plus',
    'videoCaptionSheetTitle': 'Légende',
    'videoCaptionOpen': 'Ouvrir la légende',
    'videoPublisherProfileSemantic': 'Ouvrir le profil du joueur',

    'deleteVideoTitle': 'Supprimer la vidéo',
    'deleteVideoSheetMessage':
        'Cette vidéo sera retirée du feed et ne pourra plus '
        'être lue par les autres utilisateurs.',
    'deleteVideoPrimaryAction': 'Supprimer définitivement',
    'deleteVideoSemantic': 'Supprimer la vidéo',
    'likeVideo': 'Aimer la vidéo',
    'unlikeVideo': 'Retirer la mention J’aime',
    'shareVideo': 'Partager la vidéo',
    'reportVideoTitle': 'Signaler la vidéo',
    'reportVideoSemantic': 'Signaler la vidéo',
    'reportedVideoSemantic': 'Vidéo déjà signalée',
    'reportVideoSheetMessage':
        'Notre équipe vérifiera cette vidéo. Le créateur '
        'ne verra pas ton identité.',
    'reportVideoPrimaryAction': 'Envoyer le signalement',
    'sensitiveActionWarning': 'Action sensible',
    'moderationReviewLabel': 'Revue modération',
    'moreVideoActions': 'Plus',
    'moreVideoActionsSemantic': 'Plus d’actions',
    'profile': 'Profil',
    'openProfile': 'Ouvrir le profil',
    'followProfile': 'Suivre le profil',
    'followingProfile': 'Profil suivi',
    'ownProfile': 'Votre profil',
    'followUnavailable': 'Impossible de suivre ce profil pour le moment.',
    'protectedAccessTitle': 'Accès indisponible',
    'protectedAccessMessage':
        'Votre session a été fermée pour protéger votre '
        'compte. Veuillez vous reconnecter.',
    'sessionRevokedMessage':
        'Votre session a été fermée. Veuillez vous reconnecter.',
    'authRequiredMessage': 'Session expirée. Reconnectez-vous puis réessayez.',

    'missingShareUrl': 'Lien vidéo indisponible pour le partage.',
    'shareUnavailable': 'Partage impossible pour le moment.',
    'shareOffline': 'Connexion requise pour partager.',
    'shareRecorded': 'Partage enregistré.',
    'shareTitle': 'Partager la vidéo',
    'shareSubject': 'Vidéo Adfoot',
    'shareEmptyCaption': 'Regarde cette vidéo sur Adfoot.',
    'shareWithCaptionPrefix': 'Regarde cette vidéo sur Adfoot :',
    'likeOffline': 'Impossible d’aimer la vidéo hors connexion.',
    'likeAdded': 'Mention J’aime ajoutée.',
    'likeRemoved': 'Mention J’aime retirée.',
    'likeUnavailable': 'Like impossible pour le moment.',
    'reportOffline': 'Connexion requise pour signaler.',
    'videoNotFound': 'Vidéo introuvable.',
    'videoAlreadyReported': 'Tu as déjà signalé cette vidéo.',
    'reportSent': 'Signalement envoyé, merci !',
    'reportUnavailable': 'Signalement impossible pour le moment.',
    'deleteOffline': 'Connexion requise pour supprimer cette vidéo.',

    'feedEndTitle': 'Vous êtes à jour',
    'feedEndMessageSingular':
        'C’est la fin du fil : la seule vidéo disponible a été affichée. '
        'Revenez plus tard pour les nouveautés.',
    'feedEndMessagePlural':
        'C’est la fin du fil : les @count vidéos disponibles ont toutes été '
        'affichées. Revenez plus tard pour les nouveautés.',
    'feedEndRefreshAction': 'Rafraîchir le fil',
    'feedEndSearchAction': 'Rechercher un poste',
  };

  static const Map<String, String> _en = {
    'videoSearchOpen': 'Search',
    'videoSearchIdleLabel': 'Position, player, club',
    'videoSearchTitle': 'Video search',
    'videoSearchHint': 'Position, player, club...',
    'videoSearchClear': 'Clear',
    'videoSearchResultHint': 'Open this video',
    'defaultPublisherName': 'Adfoot Profile',
    'videoSearchLoadingTitle': 'Searching',
    'videoSearchLoadingMessage': 'Looking for matching videos.',
    'videoSearchEmptyTitle': 'No videos found',
    'videoSearchEmptyMessage':
        'Try forward, defender, midfielder, goalkeeper, or another position.',
    'videoSearchUnavailable':
        "Search is unavailable right now. Try again in a moment.",
    'pendingVideosAction': 'View',
    'pendingVideosLabelSingular': '1 new video',
    'pendingVideosLabelPlural': '@count new videos',
    'pendingVideosSemanticSingular': '1 new video available',
    'pendingVideosSemanticPlural': '@count new videos available',
    'emptyHomeVideoFeedTitle': 'No videos available',
    'emptyHomeVideoFeedPlayerMessage':
        'Submit your first video to add it to the feed.',
    'emptyHomeVideoFeedDefaultMessage': 'Check back later or refresh the feed.',
    'addVideoSemantic': 'Submit a video',
    'refresh': 'Refresh',
    'noInternetTitle': 'No internet connection',
    'noInternetMessage': 'Check your connection, then reload the feed.',
    'retry': 'Retry',
    'actionConfirmedTitle': 'Action confirmed',
    'actionImpossibleTitle': 'Action unavailable',
    'noteTitle': 'Note',
    'emptyProfileVideoFeedTitle': 'No videos to show',
    'emptyProfileVideoFeedMessage': 'This profile has no videos available yet.',
    'back': 'Back',
    'uploadFormTitle': 'Submit a video',
    'uploadFormSubtitle': 'Preview and details',
    'descriptionLabel': 'Description (required)',
    'descriptionHint': 'E.g.: Dribble + left-foot shot',
    'descriptionRequired': 'Description is required.',
    'minThreeChars': 'At least 3 characters.',
    'captionLabel': 'Caption (required)',
    'captionHint': 'E.g.: #U17 #Winger #Speed',
    'captionRequired': 'Caption is required.',
    'uploadVideoButton': 'Submit the video',
    'uploadReminder':
        'Reminder: max duration 3 min • max file size 150 MB • '
        'admin review before publishing',
    'discardDraftTitle': 'Discard this video?',
    'discardDraftMessage': 'Your description and caption will not be saved.',
    'discardDraftConfirm': 'Discard',
    'discardDraftCancel': 'Continue',
    'uploadUnexpectedErrorTitle': 'Unexpected error',
    'unexpectedUploadError': 'Unexpected error: @error',
    'uploadQuotaReachedTitle': 'Video limit reached',
    'uploadQuotaReachedMessage':
        'Your account has reached its limit of @limit published videos. '
        'To publish more, ask the Adfoot agency to raise your limit.',
    'uploadQuotaContactAction': 'Contact the Adfoot agency',
    'uploadQuotaDismissAction': 'Close',
    'uploadQuotaContactFallback':
        'Message the Adfoot agency on WhatsApp at @phone, or go through '
        '@website, to raise your video limit.',
    'uploadOptimizationTitle': 'Optimizing',
    'uploadProgressTitle': 'Submission in progress',
    'uploadPreparationTitle': 'Preparing the video',
    'uploadProgressSubtitle': 'Keep the app open during the transfer.',
    'uploadPreparationSubtitle':
        'We are preparing the file and thumbnail before sending.',
    'uploadOptimizationSubtitle':
        'We are finalizing playback and quality before admin review.',
    'uploadCancelAction': 'Cancel upload',
    'addVideoScreenTitle': 'Add a video',
    'addVideoScreenSubtitle': 'Video submission',
    'noVideoSelected': 'No video selected.',
    'galleryPermissionTitle': 'Permission required',
    'galleryPermissionMessage':
        'Please allow access to the gallery to select a video.',
    'videoSelectionErrorTitle': 'Selection failed',
    'videoSelectionFailed': 'Selection failed: @error',
    'addVideoPickTitle': 'Select a video to submit',
    'uploadConstraintsHint':
        'Max duration 3 min • Max file 150 MB • Minimum quality 480×360',
    'chooseFromGallery': 'Choose from gallery',
    'maxDurationChip': '≤ 3 minutes',
    'minQualityChip': '≥ 480×360',
    'maxFileSizeChip': '≤ 150 MB',
    'autoOptimizationChip': 'Admin review',
    'overlayLoading': 'Loading...',
    'overlayWaiting': 'Please wait...',

    'loadingMessage': 'Loading the video...',
    'slowLoadingMessage': 'Slow connection...',
    'slowLoadingDetail':
        'The video is still loading. Try again if it stays stuck.',
    'playbackErrorTitle': 'Playback failed',
    'playbackUnavailable': 'Video playback unavailable.',
    'playbackInterruptedRetry': 'Playback interrupted. Try again.',
    'play': 'Play',
    'pause': 'Pause',
    'playVideo': 'Play the video',
    'pauseVideo': 'Pause the video',
    'rewindTenSeconds': 'Rewind 10 seconds',
    'forwardTenSeconds': 'Forward 10 seconds',
    'rewindTenSecondsFeedback': '-10s',
    'forwardTenSecondsFeedback': '+10s',
    'playbackSpeed': 'Playback speed',
    'currentPlaybackSpeed': 'Current speed',
    'progressBarSemantic': 'Video progress',
    'loadingTooLong': 'Loading is taking too long. Try again.',
    'playbackError': 'Playback error',
    'actionTimedOut':
        'The server is taking too long to respond. Check your connection, '
        'then try again.',
    'genericActionImpossible': 'Action unavailable.',
    'genericActionRetry': 'Action unavailable right now.',
    'seeMore': 'See more',
    'videoCaptionSheetTitle': 'Caption',
    'videoCaptionOpen': 'Open the caption',
    'videoPublisherProfileSemantic': 'Open the player profile',

    'deleteVideoTitle': 'Delete the video',
    'deleteVideoSheetMessage':
        'This video will be removed from the feed and can no longer be '
        'watched by other users.',
    'deleteVideoPrimaryAction': 'Delete permanently',
    'deleteVideoSemantic': 'Delete the video',
    'likeVideo': 'Like the video',
    'unlikeVideo': 'Remove the like',
    'shareVideo': 'Share the video',
    'reportVideoTitle': 'Report the video',
    'reportVideoSemantic': 'Report the video',
    'reportedVideoSemantic': 'Video already reported',
    'reportVideoSheetMessage':
        'Our team will review this video. The creator will not see your '
        'identity.',
    'reportVideoPrimaryAction': 'Send the report',
    'sensitiveActionWarning': 'Sensitive action',
    'moderationReviewLabel': 'Moderation review',
    'moreVideoActions': 'More',
    'moreVideoActionsSemantic': 'More actions',
    'profile': 'Profile',
    'openProfile': 'Open the profile',
    'followProfile': 'Follow the profile',
    'followingProfile': 'Following profile',
    'ownProfile': 'Your profile',
    'followUnavailable': 'Unable to follow this profile right now.',
    'protectedAccessTitle': 'Access unavailable',
    'protectedAccessMessage':
        'Your session was closed to protect your account. '
        'Please sign in again.',
    'sessionRevokedMessage': 'Your session was closed. Please sign in again.',
    'authRequiredMessage': 'Session expired. Sign in again, then retry.',

    'missingShareUrl': 'Video link unavailable for sharing.',
    'shareUnavailable': 'Sharing is unavailable right now.',
    'shareOffline': 'Connection required to share.',
    'shareRecorded': 'Share recorded.',
    'shareTitle': 'Share the video',
    'shareSubject': 'Adfoot video',
    'shareEmptyCaption': 'Check out this video on Adfoot.',
    'shareWithCaptionPrefix': 'Check out this video on Adfoot:',
    'likeOffline': 'Unable to like the video while offline.',
    'likeAdded': 'Like added.',
    'likeRemoved': 'Like removed.',
    'likeUnavailable': 'Like is unavailable right now.',
    'reportOffline': 'Connection required to report.',
    'videoNotFound': 'Video not found.',
    'videoAlreadyReported': 'You already reported this video.',
    'reportSent': 'Report sent, thank you!',
    'reportUnavailable': 'Reporting is unavailable right now.',
    'deleteOffline': 'Connection required to delete this video.',

    'feedEndTitle': 'You are up to date',
    'feedEndMessageSingular':
        'That is the end of the feed: the only available video has been '
        'shown. Check back later for new ones.',
    'feedEndMessagePlural':
        'That is the end of the feed: all @count available videos have '
        'been shown. Check back later for new ones.',
    'feedEndRefreshAction': 'Refresh the feed',
    'feedEndSearchAction': 'Search for a position',
  };
}
