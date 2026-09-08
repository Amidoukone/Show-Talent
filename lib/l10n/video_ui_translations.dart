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
    'profileFirebaseSessionExpiredMessage':
        'La session Firebase est expirée. Reconnectez-vous puis réessayez.',
    'profileSessionMismatchMessage':
        'La session active ne correspond pas au profil ouvert. '
        'Reconnectez-vous avec le bon compte puis réessayez.',
    'profileWriteAppCheckDeniedMessage':
        'Firebase refuse cette session. Vérifiez App Check pour ce '
        'build/téléphone, puis réessayez. Code: @code',
    'profileWriteGenericDeniedMessage':
        'Votre session ne permet pas de modifier ce profil. '
        'Reconnectez-vous puis réessayez. Si le problème persiste sur ce '
        'build, vérifiez App Check et le déploiement des règles '
        'Firestore. Code: @code',
    'profileCvStorageAppCheckDeniedMessage':
        'Firebase Storage ou App Check refuse ce build/téléphone. '
        'Vérifiez que le debug token de ce téléphone est enregistré, ou '
        'utilisez Play Integrity pour la version finale. Code: @code',
    'profileCvStorageGenericDeniedMessage':
        'Firebase Storage refuse actuellement l’ajout du CV pour cette '
        'session. Vérifiez que les règles Storage déployées autorisent '
        'les CV PDF du propriétaire et que App Check est actif pour ce '
        'build. Code: @code',
    'profileNoAccessCurrentSessionMessage':
        'Vous n’avez pas accès à ce profil avec la session actuelle.',
    'profileLoadUnavailableMessage':
        'Chargement du profil impossible. Réessayez dans quelques '
        'instants.',
    'profileLoadUnavailableShortMessage': 'Chargement du profil impossible.',
    'profileWriteUnavailableMessage': 'Impossible de mettre à jour le profil.',
    'profileSecureConnectionUnavailableMessage':
        'Connexion sécurisée indisponible. Réessayez dans quelques '
        'instants.',
    'profilePhotoUpdateUnavailableMessage':
        'Impossible de mettre à jour la photo.',
    'profileUnavailableTitle': 'Profil indisponible',
    'profileNotFoundMessage': 'Profil introuvable.',
    'profileInvalidSessionTitle': 'Session invalide',
    'profileUpdateFailedTitle': 'Mise à jour impossible',
    'profilePermissionDeniedTitle': 'Autorisation refusée',
    'profilePhotoPermissionDeniedMessage':
        'Votre session ne permet pas de modifier cette photo. '
        'Reconnectez-vous puis réessayez.',
    'profilePhotoUpdatedTitle': 'Photo mise à jour',
    'profilePhotoUpdatedMessage': 'Votre photo de profil a été enregistrée.',
    'profilePhotoUpdateFailedTitle': 'Photo non mise à jour',
    'profileVideosUnavailableTitle': 'Vidéos indisponibles',
    'profileVideosLoadUnavailableMessage': 'Chargement des vidéos impossible.',
    'profileCvSavedTitle': 'CV enregistré',
    'profileCvSavedMessage': 'Votre CV a été ajouté ou mis à jour.',
    'profileCvRejectedTitle': 'CV non accepté',
    'profileCvAddFailedTitle': 'Ajout impossible',
    'profileCvAddUnavailableMessage': 'Impossible d’ajouter le CV.',
    'profileCvDeletedTitle': 'CV supprimé',
    'profileCvDeletedMessage': 'Le CV a été retiré du profil.',
    'profileCvDeletePermissionDeniedMessage':
        'Votre session ne permet pas de supprimer ce CV. Reconnectez-vous '
        'puis réessayez.',
    'profileCvDeleteFailedTitle': 'Suppression impossible',
    'profileCvDeleteUnavailableMessage': 'Impossible de supprimer le CV.',
    'actionResponseDefaultSuccessMessage': 'Action réalisée.',
    'actionResponseOfflineMessage':
        'Connexion indisponible. Réessaie quand tu es en ligne.',
    'contactContextProfileLabel': 'Profil',
    'contactContextEventLabel': 'Événement',
    'contactContextParticipantsLabel': 'Participants',
    'contactContextDiscoveryLabel': 'Découverte',
    'contactContextOfferLabel': 'Offre',
    'contactContextDefaultLabel': 'Contact',
    'contactReasonOpportunityLabel': 'Opportunité',
    'contactReasonTrialLabel': 'Essai / Évaluation',
    'contactReasonApplicationLabel': 'Candidature / Présentation',
    'contactReasonFollowUpLabel': 'Suivi',
    'contactReasonInformationLabel': 'Information',
    'agencyFollowUpReviewingLabel': 'En revue',
    'agencyFollowUpInProgressLabel': 'En accompagnement',
    'agencyFollowUpQualifiedLabel': 'Qualifié',
    'agencyFollowUpClosedLabel': 'Clos',
    'agencyFollowUpNewLeadLabel': 'Nouveau lead',
    'chatGuidedFirstContactIntro': 'Premier contact Adfoot.',
    'chatGuidedFirstContactReasonPart': 'Motif : @reason.',
    'chatGuidedFirstContactContextWithTitlePart': 'Contexte : @label - @title.',
    'chatGuidedFirstContactContextPart': 'Contexte : @label.',
    'videoDurationProbeFailedMessage':
        'Impossible de déterminer la durée de cette vidéo. Réessayez ou '
        'choisissez un autre fichier.',
    'videoPreparedDurationExceedsLimitMessage':
        'La vidéo préparée dure @duration. La limite est de @limit.',
    'videoDurationUnknownLabel': 'inconnue',
    'videoPreparationCancelledMessage':
        'Préparation vidéo annulée ou incomplète.',
    'videoPreparedFileNotFoundMessage': 'Fichier vidéo préparé introuvable.',
    'videoTrimFailedMessage':
        'Impossible de préparer un extrait de @seconds secondes.',
    'accountCleanupReauthRequiredMessage':
        'Vérification de sécurité requise. Merci de vous reconnecter puis '
        'de relancer la suppression.',
    'accountCleanupGenericFailedMessage':
        'Suppression impossible pour le moment. Vérifiez votre connexion '
        'puis réessayez.',
    'accountCleanupNotDeletableInAppMessage':
        'Ce compte ne peut pas être supprimé depuis l’application.',
    'accountCleanupTimeoutMessage':
        'La suppression a pris trop de temps. Vérifiez votre connexion '
        'puis réessayez.',
    'accountCleanupUnknownErrorMessage':
        'Une erreur est survenue pendant la suppression. Merci de '
        'réessayer.',
    'accountCleanupInvalidSessionMessage':
        'Session invalide. Veuillez vous reconnecter.',
    'accountCleanupSecuritySessionExpiredMessage':
        'Session de sécurité expirée. Merci de vous reconnecter puis de '
        'relancer la suppression.',
    'eventNotOpenMessage': 'L’événement n’est pas ouvert.',
    'eventAlreadyRegisteredMessage': 'Vous êtes déjà inscrit à cet événement.',
    'eventCapacityFullMessage':
        'La capacité maximale de cet événement est atteinte.',
    'eventNoLongerOpenMessage': 'L’événement n’est plus ouvert.',
    'eventNotRegisteredMessage': 'Vous n’êtes pas inscrit à cet événement.',
    'offreNotFoundMessage': 'Offre introuvable.',
    'offreClosedApplyMessage': 'Vous ne pouvez pas postuler à cette offre.',
    'offreAlreadyAppliedMessage': 'Vous avez déjà postulé à cette offre.',
    'offreNotAppliedMessage': 'Vous n’êtes pas inscrit à cette offre.',
    'userRepositoryMissingProfileMessage':
        'Ce compte n’est plus disponible. Si vous pensez qu’il s’agit '
        'd’une erreur, contactez le support Adfoot.',
    'userRepositoryAdminPortalOnlyMessage':
        'Ce compte est réservé au portail d’administration Adfoot.',
    'userRepositoryDisabledWithReasonMessage':
        'L’accès à ce compte a été désactivé. Motif : @reason',
    'authAccessMissingProfileMessage':
        'Compte incomplet ou non provisionné. Contactez l’équipe Adfoot.',
    'authAccessDisabledMessage':
        'Ce compte a été désactivé. Contactez l’équipe Adfoot.',
    'authAccessUnavailableMessage':
        'Impossible de vérifier votre accès pour le moment. Réessayez '
        'dans quelques instants.',
    'authBoundedTimeoutMessage':
        'La connexion au serveur prend trop de temps (@stage). Vérifiez '
        'votre réseau puis réessayez.',
    'authStageAuthenticationLabel': 'authentification',
    'authStageProfileLabel': 'profil',
    'authStageTokenLabel': 'jeton',
    'authStagePasswordResetLabel': 'réinitialisation du mot de passe',
    'authStagePasswordChangeLabel': 'changement du mot de passe',
    'authStageEmailVerificationSendLabel': 'envoi de l’e-mail de vérification',
    'authSignInUnavailableMessage':
        'Impossible de se connecter pour le moment.',
    'authSessionNotFoundAfterSignInMessage':
        'Session introuvable après connexion.',
    'authSignInHandshakeTimeoutMessage':
        'La connexion prend trop de temps. Vérifiez votre réseau puis '
        'réessayez.',
    'authEmailVerificationSendFailedMessage': 'Erreur d’envoi.',
    'authUserNotSignedInMessage':
        'Utilisateur non connecté. Veuillez vous reconnecter.',
    'authSessionExpiredReconnectMessage':
        'Session expirée. Veuillez vous reconnecter.',
    'authEmailNotYetVerifiedMessage':
        'Votre e-mail n’est pas encore détecté comme vérifié. Après avoir '
        'cliqué sur le lien, attendez quelques secondes puis réessayez.',
    'callableAuthRequiredMessage': 'Authentification requise.',
    'callableServerErrorMessage': 'Erreur serveur.',
    'callableServerErrorWithStatusMessage': 'Erreur serveur (@status).',
    'callableInvalidResponseMessage':
        'Réponse serveur invalide pendant l’appel @callable.',
    'callableServiceUnavailableMessage':
        'Service serveur indisponible pendant l’appel @callable '
        '(HTTP @status).',
    'callableAuthTimeoutMessage':
        'Authentification trop longue. Vérifiez votre réseau puis '
        'réessayez.',
    'callableAuthUnavailableMessage':
        'Authentification indisponible. Reconnectez-vous puis réessayez.',
    'uploadClientCallableFailedMessage': 'Échec appel @callable.',
    'uploadClientIncompleteResponseMessage':
        'Réponse incomplète du serveur pendant @callable '
        '(champ « @field »).',
    'uploadClientRetryNotFoundMessage': 'Échec upload : tentative introuvable.',
    'uploadClientFileNotFoundMessage': 'Fichier @label introuvable.',
    'uploadClientFileEmptyMessage': 'Fichier @label vide.',
    'uploadClientTransferTooSlowMessage':
        'Le transfert vidéo prend trop de temps sur cette connexion. '
        'Vérifiez votre réseau puis réessayez.',
    'uploadClientInvalid308VideoMessage':
        'Réponse 308 invalide pendant l’upload vidéo.',
    'uploadClientThumbnailLinkExpiredMessage': 'Lien miniature expiré.',
    'uploadClientInvalid308ThumbnailMessage':
        'Réponse 308 invalide pendant l’upload miniature.',
    'contactIntakeFeedbackDiscussionStartedLabel': 'Discussion engagée',
    'contactIntakeFeedbackTrialScheduledLabel': 'Essai / rendez-vous prévu',
    'contactIntakeFeedbackOpportunitySeriousLabel': 'Opportunité sérieuse',
    'contactIntakeFeedbackNotRelevantLabel': 'Non pertinent',
    'contactIntakeFeedbackIssueReportedLabel': 'Problème signalé',
    'contactIntakeFeedbackNoResponseLabel': 'Pas encore de réponse',
    'contactIntakeFeedbackRecordedMessage':
        'Retour de mise en relation enregistré.',
    'contactIntakeFeedbackIntakeNotFoundMessage':
        'Mise en relation introuvable.',
    'contactIntakeFeedbackUnavailableMessage':
        'Retour impossible pour le moment. Réessayez plus tard.',
    'contactIntakeFeedbackPermissionDeniedMessage':
        'Seuls les participants peuvent envoyer ce retour.',
    'contactIntakeFeedbackInvalidMessage':
        'Retour invalide. Vérifiez les informations envoyées.',
    'emailLinkResetRefusedTitle': 'Lien de réinitialisation refusé',
    'emailLinkResetOpenFailedMessage':
        'Impossible d’ouvrir ce lien de réinitialisation. Demandez-en un '
        'nouveau depuis la page de connexion.',
    'requirementBirthDateLabel': 'Date de naissance',
    'requirementNationalityLabel': 'Nationalité',
    'requirementPositionLabel': 'Poste',
    'requirementCountryLabel': 'Pays',
    'requirementStrongFootLabel': 'Pied fort',
    'requirementHeightLabel': 'Taille',
    'requirementContractStatusLabel': 'Statut contractuel',
    'requirementCurrentClubLevelLabel': 'Niveau du club actuel',
    'requirementCurrentSeasonStatsLabel': 'Statistiques de la saison en cours',
    'requirementVideoOrCvLabel': 'Une vidéo publiée ou un CV',
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
    'profileFirebaseSessionExpiredMessage':
        'Your Firebase session has expired. Please sign in again and '
        'try again.',
    'profileSessionMismatchMessage':
        'The active session does not match the profile that is open. '
        'Sign in with the correct account and try again.',
    'profileWriteAppCheckDeniedMessage':
        'Firebase rejects this session. Check App Check for this '
        'build/device, then try again. Code: @code',
    'profileWriteGenericDeniedMessage':
        'Your session does not allow you to edit this profile. Sign in '
        'again and try again. If the problem persists on this build, '
        'check App Check and the Firestore rules deployment. '
        'Code: @code',
    'profileCvStorageAppCheckDeniedMessage':
        'Firebase Storage or App Check rejects this build/device. Check '
        'that this device\'s debug token is registered, or use Play '
        'Integrity for the final version. Code: @code',
    'profileCvStorageGenericDeniedMessage':
        'Firebase Storage currently rejects adding the CV for this '
        'session. Check that the deployed Storage rules allow the '
        'owner\'s CV PDFs and that App Check is active for this build. '
        'Code: @code',
    'profileNoAccessCurrentSessionMessage':
        'You do not have access to this profile with the current session.',
    'profileLoadUnavailableMessage':
        'Unable to load the profile. Try again in a moment.',
    'profileLoadUnavailableShortMessage': 'Unable to load the profile.',
    'profileWriteUnavailableMessage': 'Unable to update the profile.',
    'profileSecureConnectionUnavailableMessage':
        'Secure connection unavailable. Try again in a moment.',
    'profilePhotoUpdateUnavailableMessage': 'Unable to update the photo.',
    'profileUnavailableTitle': 'Profile unavailable',
    'profileNotFoundMessage': 'Profile not found.',
    'profileInvalidSessionTitle': 'Invalid session',
    'profileUpdateFailedTitle': 'Unable to update',
    'profilePermissionDeniedTitle': 'Permission denied',
    'profilePhotoPermissionDeniedMessage':
        'Your session does not allow you to edit this photo. Sign in '
        'again and try again.',
    'profilePhotoUpdatedTitle': 'Photo updated',
    'profilePhotoUpdatedMessage': 'Your profile photo has been saved.',
    'profilePhotoUpdateFailedTitle': 'Photo not updated',
    'profileVideosUnavailableTitle': 'Videos unavailable',
    'profileVideosLoadUnavailableMessage': 'Unable to load the videos.',
    'profileCvSavedTitle': 'CV saved',
    'profileCvSavedMessage': 'Your CV has been added or updated.',
    'profileCvRejectedTitle': 'CV not accepted',
    'profileCvAddFailedTitle': 'Unable to add',
    'profileCvAddUnavailableMessage': 'Unable to add the CV.',
    'profileCvDeletedTitle': 'CV deleted',
    'profileCvDeletedMessage': 'The CV has been removed from the profile.',
    'profileCvDeletePermissionDeniedMessage':
        'Your session does not allow you to delete this CV. Sign in '
        'again and try again.',
    'profileCvDeleteFailedTitle': 'Unable to delete',
    'profileCvDeleteUnavailableMessage': 'Unable to delete the CV.',
    'actionResponseDefaultSuccessMessage': 'Action completed.',
    'actionResponseOfflineMessage':
        'No connection available. Try again once you\'re back online.',
    'contactContextProfileLabel': 'Profile',
    'contactContextEventLabel': 'Event',
    'contactContextParticipantsLabel': 'Participants',
    'contactContextDiscoveryLabel': 'Discovery',
    'contactContextOfferLabel': 'Offer',
    'contactContextDefaultLabel': 'Contact',
    'contactReasonOpportunityLabel': 'Opportunity',
    'contactReasonTrialLabel': 'Trial / Evaluation',
    'contactReasonApplicationLabel': 'Application / Introduction',
    'contactReasonFollowUpLabel': 'Follow-up',
    'contactReasonInformationLabel': 'Information',
    'agencyFollowUpReviewingLabel': 'Under review',
    'agencyFollowUpInProgressLabel': 'In progress',
    'agencyFollowUpQualifiedLabel': 'Qualified',
    'agencyFollowUpClosedLabel': 'Closed',
    'agencyFollowUpNewLeadLabel': 'New lead',
    'chatGuidedFirstContactIntro': 'First contact via Adfoot.',
    'chatGuidedFirstContactReasonPart': 'Reason: @reason.',
    'chatGuidedFirstContactContextWithTitlePart': 'Context: @label - @title.',
    'chatGuidedFirstContactContextPart': 'Context: @label.',
    'videoDurationProbeFailedMessage':
        'Unable to determine this video\'s duration. Try again or choose '
        'a different file.',
    'videoPreparedDurationExceedsLimitMessage':
        'The prepared video is @duration long. The limit is @limit.',
    'videoDurationUnknownLabel': 'unknown',
    'videoPreparationCancelledMessage':
        'Video preparation was cancelled or incomplete.',
    'videoPreparedFileNotFoundMessage': 'Prepared video file not found.',
    'videoTrimFailedMessage': 'Unable to prepare a @seconds-second clip.',
    'accountCleanupReauthRequiredMessage':
        'Security check required. Please sign in again, then start the '
        'deletion over.',
    'accountCleanupGenericFailedMessage':
        'Unable to delete right now. Check your connection and try again.',
    'accountCleanupNotDeletableInAppMessage':
        'This account cannot be deleted from the app.',
    'accountCleanupTimeoutMessage':
        'The deletion took too long. Check your connection and try again.',
    'accountCleanupUnknownErrorMessage':
        'Something went wrong during the deletion. Please try again.',
    'accountCleanupInvalidSessionMessage':
        'Invalid session. Please sign in again.',
    'accountCleanupSecuritySessionExpiredMessage':
        'Security session expired. Please sign in again, then start the '
        'deletion over.',
    'eventNotOpenMessage': 'The event is not open.',
    'eventAlreadyRegisteredMessage':
        'You are already registered for this event.',
    'eventCapacityFullMessage': 'This event has reached its maximum capacity.',
    'eventNoLongerOpenMessage': 'The event is no longer open.',
    'eventNotRegisteredMessage': 'You are not registered for this event.',
    'offreNotFoundMessage': 'Offer not found.',
    'offreClosedApplyMessage': 'You cannot apply to this offer.',
    'offreAlreadyAppliedMessage': 'You have already applied to this offer.',
    'offreNotAppliedMessage': 'You are not applied to this offer.',
    'userRepositoryMissingProfileMessage':
        'This account is no longer available. If you think this is a '
        'mistake, contact Adfoot support.',
    'userRepositoryAdminPortalOnlyMessage':
        'This account is reserved for the Adfoot admin portal.',
    'userRepositoryDisabledWithReasonMessage':
        'Access to this account has been disabled. Reason: @reason',
    'authAccessMissingProfileMessage':
        'Account incomplete or not provisioned. Contact the Adfoot team.',
    'authAccessDisabledMessage':
        'This account has been disabled. Contact the Adfoot team.',
    'authAccessUnavailableMessage':
        'Unable to check your access right now. Try again in a moment.',
    'authBoundedTimeoutMessage':
        'The connection to the server is taking too long (@stage). Check '
        'your network and try again.',
    'authStageAuthenticationLabel': 'authentication',
    'authStageProfileLabel': 'profile',
    'authStageTokenLabel': 'token',
    'authStagePasswordResetLabel': 'password reset',
    'authStagePasswordChangeLabel': 'password change',
    'authStageEmailVerificationSendLabel': 'sending the verification email',
    'authSignInUnavailableMessage': 'Unable to sign in right now.',
    'authSessionNotFoundAfterSignInMessage':
        'Session not found after signing in.',
    'authSignInHandshakeTimeoutMessage':
        'The connection is taking too long. Check your network and try '
        'again.',
    'authEmailVerificationSendFailedMessage': 'Sending failed.',
    'authUserNotSignedInMessage': 'No user signed in. Please sign in again.',
    'authSessionExpiredReconnectMessage':
        'Session expired. Please sign in again.',
    'authEmailNotYetVerifiedMessage':
        'Your email is not yet detected as verified. After clicking the '
        'link, wait a few seconds and try again.',
    'callableAuthRequiredMessage': 'Authentication required.',
    'callableServerErrorMessage': 'Server error.',
    'callableServerErrorWithStatusMessage': 'Server error (@status).',
    'callableInvalidResponseMessage':
        'Invalid server response during call @callable.',
    'callableServiceUnavailableMessage':
        'Server unavailable during call @callable (HTTP @status).',
    'callableAuthTimeoutMessage':
        'Authentication is taking too long. Check your network and try '
        'again.',
    'callableAuthUnavailableMessage':
        'Authentication unavailable. Sign in again and try again.',
    'uploadClientCallableFailedMessage': 'Call @callable failed.',
    'uploadClientIncompleteResponseMessage':
        'Incomplete server response during @callable (field "@field").',
    'uploadClientRetryNotFoundMessage': 'Upload failed: attempt not found.',
    'uploadClientFileNotFoundMessage': '@label file not found.',
    'uploadClientFileEmptyMessage': '@label file is empty.',
    'uploadClientTransferTooSlowMessage':
        'The video transfer is taking too long on this connection. Check '
        'your network and try again.',
    'uploadClientInvalid308VideoMessage':
        'Invalid 308 response during the video upload.',
    'uploadClientThumbnailLinkExpiredMessage': 'Thumbnail link expired.',
    'uploadClientInvalid308ThumbnailMessage':
        'Invalid 308 response during the thumbnail upload.',
    'contactIntakeFeedbackDiscussionStartedLabel': 'Discussion started',
    'contactIntakeFeedbackTrialScheduledLabel': 'Trial / meeting scheduled',
    'contactIntakeFeedbackOpportunitySeriousLabel': 'Serious opportunity',
    'contactIntakeFeedbackNotRelevantLabel': 'Not relevant',
    'contactIntakeFeedbackIssueReportedLabel': 'Issue reported',
    'contactIntakeFeedbackNoResponseLabel': 'No response yet',
    'contactIntakeFeedbackRecordedMessage':
        'Feedback on the introduction recorded.',
    'contactIntakeFeedbackIntakeNotFoundMessage': 'Introduction not found.',
    'contactIntakeFeedbackUnavailableMessage':
        'Unable to send feedback right now. Try again later.',
    'contactIntakeFeedbackPermissionDeniedMessage':
        'Only participants can send this feedback.',
    'contactIntakeFeedbackInvalidMessage':
        'Invalid feedback. Check the information sent.',
    'emailLinkResetRefusedTitle': 'Reset link refused',
    'emailLinkResetOpenFailedMessage':
        'Unable to open this reset link. Request a new one from the sign '
        'in page.',
    'requirementBirthDateLabel': 'Date of birth',
    'requirementNationalityLabel': 'Nationality',
    'requirementPositionLabel': 'Position',
    'requirementCountryLabel': 'Country',
    'requirementStrongFootLabel': 'Strong foot',
    'requirementHeightLabel': 'Height',
    'requirementContractStatusLabel': 'Contract status',
    'requirementCurrentClubLevelLabel': 'Current club level',
    'requirementCurrentSeasonStatsLabel': 'Current season stats',
    'requirementVideoOrCvLabel': 'A published video or a CV',
  };
}
