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

    'videoStateProcessing': 'Traitement…',
    'videoStateUnderReview': 'En validation',
    'videoStateModerated': 'Retirée',
    'videoStateFailed': 'Échec',
    'videoNotPlayableProcessing':
        'Cette vidéo est encore en cours de traitement.',
    'videoNotPlayableUnderReview':
        'Cette vidéo attend la validation d’un administrateur. Vous serez '
        'notifié dès qu’elle sera visible.',
    'videoNotPlayableModerated':
        'Cette vidéo a été retirée du public par la modération. Contactez '
        'le support si vous pensez qu’il s’agit d’une erreur.',
    'videoNotPlayableFailed':
        'Le traitement de cette vidéo a échoué. Supprimez-la et réessayez.',

    'uploadMissingRequiredFields':
        'Merci de renseigner une description et une légende.',
    'uploadSourceNotFound': 'Vidéo introuvable. Merci de réessayer.',
    'uploadEmptyFile': 'Le fichier vidéo est vide.',
    'uploadFileTooLarge': 'Le fichier vidéo dépasse la limite de 150 Mo.',
    'uploadQualityTooLow': 'Qualité vidéo insuffisante (minimum 480x360).',
    'uploadThumbnailFailed': 'Erreur lors de la génération de la miniature.',
    'uploadPreparationFailed':
        'Préparation impossible pour le moment. Merci de réessayer.',
    'uploadPreparationInProgress': 'Préparation en cours...',
    'uploadAlreadyInProgress': 'Téléversement déjà en cours.',
    'uploadMissingFile': 'Fichier manquant.',
    'uploadMissingThumbnail': 'Miniature manquante.',
    'uploadMissingMetadata': 'Description ou légende manquante.',
    'uploadVideoTransferFailed': 'Échec du téléversement de la vidéo.',
    'uploadThumbnailTransferFailed': 'Échec du téléversement de la miniature.',
    'uploadFinalizeFailed': 'Échec de la finalisation serveur.',
    'uploadCancelled': 'Téléversement annulé.',
    'uploadPreparationCancelled': 'Préparation annulée.',
    'uploadSuccess': 'Vidéo prête et visible.',
    'uploadSubmittedForReview':
        'Vidéo soumise à la revue admin. Retrouvez-la dans votre profil ; '
        'vous serez notifié dès sa validation.',
    'uploadOptimizationPending':
        'Votre vidéo est en cours de traitement. Suivez son avancement '
        'dans votre profil ; vous serez notifié dès sa validation.',
    'uploadQuotaReachedShort':
        'Plafond de @limit vidéos atteint. Contactez l’agence Adfoot pour '
        'l’augmenter.',
    'uploadAuthRequired':
        'Authentification requise. Reconnectez-vous puis réessayez.',
    'uploadPermissionDenied': 'Votre compte ne peut pas téléverser de vidéos.',
    'uploadServiceUnavailable':
        'Le service vidéo est temporairement indisponible.',
    'uploadPreconditionFailed':
        'Votre compte ne remplit pas les conditions pour téléverser.',
    'uploadServerError': 'Erreur serveur pendant le téléversement.',
    'uploadConnectionUnstable':
        'Connexion instable pendant le téléversement. Vérifiez votre '
        'réseau puis réessayez.',
    'uploadSessionTimeout':
        'Connexion sécurisée trop longue à s’établir. '
        'Vérifiez votre réseau puis réessayez.',
    'uploadUnknownError': 'Erreur pendant le téléversement.',
    'uploadOptimizationFailed':
        'Échec d’optimisation vidéo (statut : @status). Merci de réessayer.',

    'uploadStageAnalyze': 'Analyse de la vidéo...',
    'uploadStagePrepareFile': 'Préparation du fichier...',
    'uploadStageGenerateThumbnail': 'Génération de la miniature...',
    'uploadStageLoadProfile': 'Vérification du profil...',
    'uploadStageInitialize': 'Initialisation...',
    'uploadStageUploading': 'Téléversement...',
    'uploadStageRefreshSecureLink': 'Renouvellement du lien sécurisé...',
    'uploadStagePrepareSecureThumbnail': 'Préparation miniature sécurisée...',
    'uploadStageSendThumbnail': 'Envoi de la miniature...',
    'uploadStageFinalize': 'Finalisation...',
    'uploadProgressLabel': 'Progression',
    'uploadCurrentStepLabel': 'Étape actuelle',
    'uploadStepPrepare': 'Préparation',
    'uploadStepTransfer': 'Transfert',
    'uploadStepThumbnail': 'Miniature',
    'uploadStepFinalize': 'Finalisation',
    'uploadStageOptimize': 'Optimisation en cours...',
    'uploadStagePreparing': 'Préparation...',
    'uploadStageCompressing': 'Compression...',
    'uploadStageUploadingVideo': 'Téléversement vidéo...',
    'uploadStageUploadingThumbnail': 'Téléversement miniature...',

    'playbackProgressValue': '@current sur @total',
    'likeCountValueSingular': '1 mention J’aime',
    'likeCountValuePlural': '@count mentions J’aime',
    'shareCountValueSingular': '1 partage',
    'shareCountValuePlural': '@count partages',
    'selectPlaybackSpeed': 'Choisir la vitesse @speed',
    'uploadTrimmed': 'Vidéo préparée en extrait de @secondss.',

    'profileLevelElite': 'Profil Élite',
    'profileLevelAdvanced': 'Profil avancé',
    'profileLevelComplete': 'Profil complet',
    'profileLevelBasic': 'Profil basique',
    'profileTrustVerified': 'Vérifié par Adfoot',
    'profileTrustSuspended': 'Certification suspendue',
    'profileTrustNeedsReview': 'A revalider par Adfoot',
    'profileTrustUnverified': 'Non certifié',

    'authErrorConfigurationMissing':
        'La configuration Firebase Authentication de cet environnement est '
        'incomplète. Vérifiez Authentication, le provider Email/Password et '
        'la configuration du projet Firebase cible.',
    'authErrorEmailAlreadyInUse': 'Adresse e-mail déjà utilisée.',
    'authErrorWeakPassword': 'Mot de passe trop court (minimum 6 caractères).',
    'authErrorInvalidEmail': 'Adresse e-mail invalide.',
    'authErrorSignupDisabled': 'Inscription par e-mail désactivée.',
    'authErrorUserNotFound':
        'Ce compte est introuvable. Il a peut-être été supprimé ou cet '
        'e-mail est incorrect.',
    'authErrorWrongPassword': 'Mot de passe incorrect.',
    'authErrorInvalidCredential':
        'Identifiants invalides. Vérifiez votre e-mail et votre mot de '
        'passe.',
    'authErrorUserDisabled':
        'L’accès à ce compte a été désactivé. Contactez le support Adfoot.',
    'authErrorTooManyRequests': 'Trop de tentatives. Réessayez plus tard.',
    'authErrorNetworkFailed':
        'Problème de connexion réseau. Vérifiez votre connexion.',
    'authErrorInternalError':
        'La plateforme Firebase a retourné une erreur interne pour cet '
        'environnement. Vérifiez la configuration Authentication du projet '
        'cible.',
    'authErrorGeneric': 'Une erreur est survenue. Réessayez.',

    'publicSignupDisabledMessage':
        'La création de compte est gérée exclusivement par l’équipe '
        'Adfoot.',

    'sessionLoadExpiredMessage': 'Session expirée. Reconnectez-vous.',
    'profileLoadFailedMessage':
        'Impossible de charger le profil. Réessayez dans quelques instants.',
    'profileLoadConnectionUnstableMessage':
        'Connexion instable. Vérifiez votre réseau puis réessayez.',
    'sessionCannotLoadProfileMessage':
        'Votre session ne permet pas de charger ce profil.',
    'profileLoadConnectionTooSlowMessage':
        'Connexion trop lente. Vérifiez votre réseau puis réessayez.',
    'signOutFailedTitle': 'Déconnexion impossible',
    'signOutFailedMessage':
        'La session n’a pas pu être fermée. Réessayez dans quelques '
        'instants.',
    'sessionNoLongerAuthorizedMessage': 'Votre session n’est plus autorisée.',
    'accountDisabledTitle': 'Compte désactivé',
    'sessionClosedTitle': 'Session fermée',
    'sessionExpiredReconnectMessage':
        'Votre session n’est plus autorisée. Veuillez vous reconnecter.',
    'accountUnavailableTitle': 'Compte indisponible',
    'accessDeniedTitle': 'Accès refusé',

    'sessionClosedReconnectMessage':
        'Votre session a été fermée. Veuillez vous reconnecter.',
    'chatInvalidConversationIdsMessage':
        'Identifiants de conversation invalides.',
    'chatCannotChatWithSelfMessage':
        'Impossible de créer une conversation avec soi-même.',
    'chatStartConversationFailedMessage':
        'Impossible de démarrer la conversation pour le moment.',
    'chatStartGuidedContactFailedMessage':
        'Impossible de lancer ce premier contact pour le moment.',
    'chatInvalidSessionMessage':
        'Session de messagerie invalide. Merci de réessayer.',
    'chatEmptyMessageError': 'Le message est vide.',
    'chatMessageTooLongError':
        'Le message dépasse la limite autorisée (2000 caractères).',
    'chatSendingDisabledMessage':
        'L’envoi de messages est désactivé pour cette conversation.',
    'chatNewMessageNotificationTitle': 'Nouveau message',
    'chatSendFailedConnectionMessage':
        'Envoi impossible pour le moment. Vérifiez votre connexion.',
    'chatSendFailedRetryMessage':
        'Envoi impossible pour le moment. Merci de réessayer.',
    'chatDeleteFailedConnectionMessage':
        'Suppression impossible pour le moment. Vérifiez votre connexion.',
    'chatDeleteFailedRetryMessage':
        'Suppression impossible pour le moment. Merci de réessayer.',

    'eventFlyerAddedMessage': 'Affiche ajoutée.',
    'eventFlyerAddFailedMessage': 'L’affiche n’a pas pu être ajoutée.',
    'eventFlyerRemovedMessage': 'Affiche retirée.',
    'eventFlyerRemoveFailedMessage': 'L’affiche n’a pas pu être retirée.',
    'eventCreatedNotificationFailedMessage':
        'Événement créé avec succès, mais les notifications sont '
        'indisponibles.',
    'eventCreatedSuccessMessage': 'Votre événement a été créé avec succès.',
    'eventCreateFailedMessage': 'Échec de la création de l’événement.',
    'eventUpdateOwnOnlyMessage':
        'Vous ne pouvez modifier que vos propres événements.',
    'eventUpdateSuccessMessage': 'Les modifications ont été enregistrées.',
    'eventUpdateFailedMessage': 'Échec de la mise à jour de l’événement.',
    'eventNotFoundMessage': 'L’événement n’existe pas.',
    'eventDeleteOwnOnlyMessage':
        'Vous ne pouvez supprimer que vos propres événements.',
    'eventDeleteSuccessMessage': 'L’événement a été supprimé.',
    'eventDeleteFailedMessage': 'Échec de la suppression de l’événement.',
    'eventRegisterPlayersOnlyMessage':
        'Seuls les joueurs peuvent s’inscrire à un événement.',
    'eventRegisterSuccessMessage': 'Vous êtes inscrit à l’événement.',
    'eventRegisterFailedMessage': 'Échec de l’inscription.',
    'eventUnregisterPlayersOnlyMessage':
        'Seuls les joueurs peuvent se désinscrire d’un événement.',
    'eventUnregisterSuccessMessage': 'Vous êtes désinscrit de l’événement.',
    'eventUnregisterFailedMessage': 'Échec de la désinscription.',
    'eventPublisherOnlyMessage':
        'Seuls les clubs, recruteurs ou agents peuvent effectuer cette '
        'action.',
    'eventNewNotificationTitle': 'Nouvel événement',
    'eventNewNotificationBody': '@name a créé un nouvel événement : @title',
    'offreCreatePublisherOnlyMessage':
        'Seuls les clubs, recruteurs ou agents peuvent publier une offre.',
    'offreCreatedNotificationFailedMessage':
        'Offre créée avec succès, mais les notifications sont '
        'indisponibles.',
    'offreCreatedSuccessMessage': 'Votre offre a été créée avec succès.',
    'offreCreateFailedMessage': 'Échec de la création de l’offre.',
    'offreNewNotificationTitle': 'Nouvelle offre',
    'offreNewNotificationBody': '@name a publié une nouvelle offre : @title',
    'offreUpdateOwnOnlyMessage':
        'Vous ne pouvez modifier que vos propres offres.',
    'offreUpdateSuccessMessage': 'Les modifications ont été enregistrées.',
    'offreUpdateFailedMessage': 'Échec de la mise à jour de l’offre.',
    'offreInvalidStatusMessage': 'Statut invalide.',
    'offreStatusUpdatedMessage': 'Le statut est maintenant "@status".',
    'offreStatusUpdateFailedMessage':
        'Impossible de modifier le statut pour le moment.',
    'offreDeleteOwnOnlyMessage':
        'Vous ne pouvez supprimer que vos propres offres.',
    'offreDeleteSuccessMessage': 'Offre supprimée avec succès.',
    'offreDeleteFailedMessage':
        'Impossible de supprimer l’offre pour le moment.',
    'offreApplyPlayersOnlyMessage':
        'Seuls les joueurs peuvent postuler à une offre.',
    'offreApplySuccessMessage': 'Vous avez postulé à l’offre.',
    'offreApplyFailedMessage': 'Impossible de postuler pour le moment.',
    'offreWithdrawPlayersOnlyMessage':
        'Seuls les joueurs peuvent se désinscrire.',
    'offreWithdrawSuccessMessage': 'Vous vous êtes désinscrit de l’offre.',
    'offreWithdrawFailedMessage':
        'Impossible de se désinscrire pour le moment.',
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

    'videoStateProcessing': 'Processing…',
    'videoStateUnderReview': 'Under review',
    'videoStateModerated': 'Removed',
    'videoStateFailed': 'Failed',
    'videoNotPlayableProcessing': 'This video is still being processed.',
    'videoNotPlayableUnderReview':
        'This video is awaiting admin review. You will be notified once it '
        'is visible.',
    'videoNotPlayableModerated':
        'This video was removed from public view by moderation. Contact '
        'support if you think this is a mistake.',
    'videoNotPlayableFailed':
        'Processing this video failed. Delete it and try again.',

    'uploadMissingRequiredFields':
        'Please fill in a description and a caption.',
    'uploadSourceNotFound': 'Video not found. Please try again.',
    'uploadEmptyFile': 'The video file is empty.',
    'uploadFileTooLarge': 'The video file exceeds the 150 MB limit.',
    'uploadQualityTooLow': 'Video quality is too low (minimum 480x360).',
    'uploadThumbnailFailed': 'Error generating the thumbnail.',
    'uploadPreparationFailed':
        'Preparation is unavailable right now. Please try again.',
    'uploadPreparationInProgress': 'Preparing...',
    'uploadAlreadyInProgress': 'Upload already in progress.',
    'uploadMissingFile': 'File missing.',
    'uploadMissingThumbnail': 'Thumbnail missing.',
    'uploadMissingMetadata': 'Description or caption missing.',
    'uploadVideoTransferFailed': 'Video upload failed.',
    'uploadThumbnailTransferFailed': 'Thumbnail upload failed.',
    'uploadFinalizeFailed': 'Server finalization failed.',
    'uploadCancelled': 'Upload cancelled.',
    'uploadPreparationCancelled': 'Preparation cancelled.',
    'uploadSuccess': 'Video ready and visible.',
    'uploadSubmittedForReview':
        'Video submitted for admin review. Find it in your profile; you '
        'will be notified as soon as it is approved.',
    'uploadOptimizationPending':
        'Your video is being processed. Follow its progress in your '
        'profile; you will be notified as soon as it is approved.',
    'uploadQuotaReachedShort':
        'Limit of @limit videos reached. Contact the Adfoot agency to '
        'raise it.',
    'uploadAuthRequired': 'Authentication required. Sign in again, then retry.',
    'uploadPermissionDenied': 'Your account cannot upload videos.',
    'uploadServiceUnavailable': 'The video service is temporarily unavailable.',
    'uploadPreconditionFailed':
        'Your account does not meet the conditions to upload.',
    'uploadServerError': 'Server error during upload.',
    'uploadConnectionUnstable':
        'Unstable connection during upload. Check your connection, then '
        'try again.',
    'uploadSessionTimeout':
        'Establishing a secure connection took too long. Check your '
        'connection, then try again.',
    'uploadUnknownError': 'Error during upload.',
    'uploadOptimizationFailed':
        'Video optimization failed (status: @status). Please try again.',

    'uploadStageAnalyze': 'Analyzing the video...',
    'uploadStagePrepareFile': 'Preparing the file...',
    'uploadStageGenerateThumbnail': 'Generating the thumbnail...',
    'uploadStageLoadProfile': 'Checking the profile...',
    'uploadStageInitialize': 'Initializing...',
    'uploadStageUploading': 'Uploading...',
    'uploadStageRefreshSecureLink': 'Renewing the secure link...',
    'uploadStagePrepareSecureThumbnail': 'Preparing secure thumbnail...',
    'uploadStageSendThumbnail': 'Sending the thumbnail...',
    'uploadStageFinalize': 'Finalizing...',
    'uploadProgressLabel': 'Progress',
    'uploadCurrentStepLabel': 'Current step',
    'uploadStepPrepare': 'Prepare',
    'uploadStepTransfer': 'Transfer',
    'uploadStepThumbnail': 'Thumbnail',
    'uploadStepFinalize': 'Finalize',
    'uploadStageOptimize': 'Optimizing...',
    'uploadStagePreparing': 'Preparing...',
    'uploadStageCompressing': 'Compressing...',
    'uploadStageUploadingVideo': 'Uploading video...',
    'uploadStageUploadingThumbnail': 'Uploading thumbnail...',

    'playbackProgressValue': '@current of @total',
    'likeCountValueSingular': '1 like',
    'likeCountValuePlural': '@count likes',
    'shareCountValueSingular': '1 share',
    'shareCountValuePlural': '@count shares',
    'selectPlaybackSpeed': 'Choose the @speed speed',
    'uploadTrimmed': 'Video trimmed to a @seconds-second clip.',

    'profileLevelElite': 'Elite Profile',
    'profileLevelAdvanced': 'Advanced Profile',
    'profileLevelComplete': 'Complete Profile',
    'profileLevelBasic': 'Basic Profile',
    'profileTrustVerified': 'Verified by Adfoot',
    'profileTrustSuspended': 'Certification suspended',
    'profileTrustNeedsReview': 'Awaiting Adfoot review',
    'profileTrustUnverified': 'Not certified',

    'authErrorConfigurationMissing':
        'This environment\'s Firebase Authentication configuration is '
        'incomplete. Check Authentication, the Email/Password provider, '
        'and the target Firebase project\'s configuration.',
    'authErrorEmailAlreadyInUse': 'This email address is already in use.',
    'authErrorWeakPassword': 'Password too short (minimum 6 characters).',
    'authErrorInvalidEmail': 'Invalid email address.',
    'authErrorSignupDisabled': 'Email sign-up is disabled.',
    'authErrorUserNotFound':
        'This account could not be found. It may have been deleted, or '
        'this email address may be incorrect.',
    'authErrorWrongPassword': 'Incorrect password.',
    'authErrorInvalidCredential':
        'Invalid credentials. Check your email and password.',
    'authErrorUserDisabled':
        'Access to this account has been disabled. Contact Adfoot support.',
    'authErrorTooManyRequests': 'Too many attempts. Try again later.',
    'authErrorNetworkFailed':
        'Network connection issue. Check your connection.',
    'authErrorInternalError':
        'The Firebase platform returned an internal error for this '
        'environment. Check the target project\'s Authentication '
        'configuration.',
    'authErrorGeneric': 'Something went wrong. Please try again.',

    'publicSignupDisabledMessage':
        'Account creation is managed exclusively by the Adfoot team.',

    'sessionLoadExpiredMessage': 'Session expired. Please sign in again.',
    'profileLoadFailedMessage':
        'Unable to load your profile. Try again in a moment.',
    'profileLoadConnectionUnstableMessage':
        'Unstable connection. Check your network, then try again.',
    'sessionCannotLoadProfileMessage':
        'Your session does not allow loading this profile.',
    'profileLoadConnectionTooSlowMessage':
        'Connection too slow. Check your network, then try again.',
    'signOutFailedTitle': 'Sign-out failed',
    'signOutFailedMessage':
        'The session could not be closed. Try again in a moment.',
    'sessionNoLongerAuthorizedMessage': 'Your session is no longer authorized.',
    'accountDisabledTitle': 'Account disabled',
    'sessionClosedTitle': 'Session closed',
    'sessionExpiredReconnectMessage':
        'Your session is no longer authorized. Please sign in again.',
    'accountUnavailableTitle': 'Account unavailable',
    'accessDeniedTitle': 'Access denied',

    'sessionClosedReconnectMessage':
        'Your session was closed. Please sign in again.',
    'chatInvalidConversationIdsMessage': 'Invalid conversation identifiers.',
    'chatCannotChatWithSelfMessage':
        'You cannot start a conversation with yourself.',
    'chatStartConversationFailedMessage':
        'Unable to start the conversation right now.',
    'chatStartGuidedContactFailedMessage':
        'Unable to start this first contact right now.',
    'chatInvalidSessionMessage': 'Invalid messaging session. Please try again.',
    'chatEmptyMessageError': 'The message is empty.',
    'chatMessageTooLongError':
        'The message exceeds the allowed limit (2000 characters).',
    'chatSendingDisabledMessage':
        'Sending messages is disabled for this conversation.',
    'chatNewMessageNotificationTitle': 'New message',
    'chatSendFailedConnectionMessage':
        'Unable to send right now. Check your connection.',
    'chatSendFailedRetryMessage': 'Unable to send right now. Please try again.',
    'chatDeleteFailedConnectionMessage':
        'Unable to delete right now. Check your connection.',
    'chatDeleteFailedRetryMessage':
        'Unable to delete right now. Please try again.',

    'eventFlyerAddedMessage': 'Flyer added.',
    'eventFlyerAddFailedMessage': 'The flyer could not be added.',
    'eventFlyerRemovedMessage': 'Flyer removed.',
    'eventFlyerRemoveFailedMessage': 'The flyer could not be removed.',
    'eventCreatedNotificationFailedMessage':
        'Event created successfully, but notifications are unavailable.',
    'eventCreatedSuccessMessage': 'Your event was created successfully.',
    'eventCreateFailedMessage': 'Failed to create the event.',
    'eventUpdateOwnOnlyMessage': 'You can only edit your own events.',
    'eventUpdateSuccessMessage': 'Your changes have been saved.',
    'eventUpdateFailedMessage': 'Failed to update the event.',
    'eventNotFoundMessage': 'This event does not exist.',
    'eventDeleteOwnOnlyMessage': 'You can only delete your own events.',
    'eventDeleteSuccessMessage': 'The event has been deleted.',
    'eventDeleteFailedMessage': 'Failed to delete the event.',
    'eventRegisterPlayersOnlyMessage':
        'Only players can register for an event.',
    'eventRegisterSuccessMessage': 'You are registered for the event.',
    'eventRegisterFailedMessage': 'Registration failed.',
    'eventUnregisterPlayersOnlyMessage':
        'Only players can unregister from an event.',
    'eventUnregisterSuccessMessage': 'You are unregistered from the event.',
    'eventUnregisterFailedMessage': 'Unregistration failed.',
    'eventPublisherOnlyMessage':
        'Only clubs, recruiters, or agents can perform this action.',
    'eventNewNotificationTitle': 'New event',
    'eventNewNotificationBody': '@name created a new event: @title',
    'offreCreatePublisherOnlyMessage':
        'Only clubs, recruiters, or agents can publish an offer.',
    'offreCreatedNotificationFailedMessage':
        'Offer created successfully, but notifications are unavailable.',
    'offreCreatedSuccessMessage': 'Your offer has been created successfully.',
    'offreCreateFailedMessage': 'Failed to create the offer.',
    'offreNewNotificationTitle': 'New offer',
    'offreNewNotificationBody': '@name published a new offer: @title',
    'offreUpdateOwnOnlyMessage': 'You can only edit your own offers.',
    'offreUpdateSuccessMessage': 'Your changes have been saved.',
    'offreUpdateFailedMessage': 'Failed to update the offer.',
    'offreInvalidStatusMessage': 'Invalid status.',
    'offreStatusUpdatedMessage': 'The status is now "@status".',
    'offreStatusUpdateFailedMessage': 'Unable to update the status right now.',
    'offreDeleteOwnOnlyMessage': 'You can only delete your own offers.',
    'offreDeleteSuccessMessage': 'Offer deleted successfully.',
    'offreDeleteFailedMessage': 'Unable to delete the offer right now.',
    'offreApplyPlayersOnlyMessage': 'Only players can apply to an offer.',
    'offreApplySuccessMessage': 'You have applied to the offer.',
    'offreApplyFailedMessage': 'Unable to apply right now.',
    'offreWithdrawPlayersOnlyMessage': 'Only players can withdraw.',
    'offreWithdrawSuccessMessage': 'You have withdrawn from the offer.',
    'offreWithdrawFailedMessage': 'Unable to withdraw right now.',
  };
}
