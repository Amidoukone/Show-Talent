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
  Map<String, Map<String, String>> get keys => {
    'fr': _fr,
    'en': _en,
  };

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
    'emptyHomeVideoFeedDefaultMessage': 'Revenez plus tard ou actualisez le feed.',
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
    'emptyProfileVideoFeedMessage':
        'This profile has no videos available yet.',
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
    'discardDraftMessage':
        'Your description and caption will not be saved.',
    'discardDraftConfirm': 'Discard',
    'discardDraftCancel': 'Continue',
    'uploadUnexpectedErrorTitle': 'Unexpected error',
    'unexpectedUploadError': 'Unexpected error: @error',
  };
}
