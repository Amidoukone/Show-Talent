import 'package:adfoot/l10n/video_ui_translations.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Verifies the GetX translation pipeline for VideoUiStrings end to end.
///
/// video_state_overlay_test.dart's existing assertions like
/// `find.text(VideoUiStrings.retry)` do not catch a broken translation:
/// both sides of that comparison call the same getter, so they agree
/// trivially even when `.tr` falls back to returning the bare key (which is
/// exactly what happens with no GetMaterialApp/translations in scope). Only
/// pumping a real GetMaterialApp with VideoUiTranslations wired in -- the
/// way lib/main.dart wires it -- proves the lookup actually resolves.
void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  Future<void> pumpWithLocale(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      GetMaterialApp(
        translations: VideoUiTranslations(),
        locale: locale,
        fallbackLocale: const Locale('fr'),
        home: const SizedBox.shrink(),
      ),
    );
  }

  testWidgets('French resolves to real copy, not the bare key', (tester) async {
    await pumpWithLocale(tester, const Locale('fr'));

    expect(VideoUiStrings.retry, 'Réessayer');
    expect(VideoUiStrings.noInternetTitle, 'Pas de connexion Internet');
    expect(VideoUiStrings.videoSearchIdleLabel, 'Poste, joueur, club');
    expect(VideoUiStrings.pendingVideosLabel(1), '1 nouvelle vidéo');
    expect(VideoUiStrings.pendingVideosLabel(3), '3 nouvelles vidéos');
    expect(
      VideoUiStrings.pendingVideosSemantic(1),
      '1 nouvelle vidéo disponible',
    );
    expect(
      VideoUiStrings.pendingVideosSemantic(5),
      '5 nouvelles vidéos disponibles',
    );
    expect(VideoUiStrings.videoSearchOpen, 'Rechercher');
    expect(VideoUiStrings.videoSearchHint, 'Poste, joueur, club...');
    expect(VideoUiStrings.defaultPublisherName, 'Profil Adfoot');
    expect(VideoUiStrings.videoSearchResultHint, 'Ouvrir cette vidéo');
    expect(VideoUiStrings.back, 'Retour');
    expect(
      VideoUiStrings.emptyProfileVideoFeedTitle,
      'Aucune vidéo à afficher',
    );
    expect(VideoUiStrings.uploadFormTitle, 'Soumettre une vidéo');
    expect(VideoUiStrings.uploadFormSubtitle, 'Prévisualisation et détails');
    expect(VideoUiStrings.descriptionLabel, 'Description (obligatoire)');
    expect(VideoUiStrings.captionLabel, 'Légende (obligatoire)');
    expect(VideoUiStrings.discardDraftTitle, 'Abandonner cette vidéo ?');
    expect(VideoUiStrings.discardDraftConfirm, 'Abandonner');
    expect(
      VideoUiStrings.unexpectedUploadError('network error'),
      'Erreur inattendue : network error',
    );
    expect(VideoUiStrings.addVideoScreenTitle, 'Ajouter une vidéo');
    expect(VideoUiStrings.chooseFromGallery, 'Choisir depuis la galerie');
    expect(
      VideoUiStrings.uploadQuotaReachedMessage(10),
      'Votre compte a atteint son plafond de 10 vidéos publiées. '
      'Pour en publier davantage, demandez à l’agence Adfoot d’augmenter '
      'votre plafond.',
    );
    expect(
      VideoUiStrings.uploadQuotaContactFallback(
        '+225 00 00 00 00',
        'adfoot.org',
      ),
      'Écrivez à l’agence Adfoot sur WhatsApp au +225 00 00 00 00, ou passez '
      'par adfoot.org, pour faire augmenter votre plafond de vidéos.',
    );
    expect(VideoUiStrings.loadingMessage, 'Chargement de la vidéo...');
    expect(VideoUiStrings.playbackErrorTitle, 'Lecture impossible');
    expect(VideoUiStrings.playVideo, 'Lancer la vidéo');
    expect(VideoUiStrings.rewindTenSecondsFeedback, '-10s');
    expect(VideoUiStrings.playbackSpeed, 'Vitesse de lecture');
    expect(VideoUiStrings.videoCaptionSheetTitle, 'Légende');
    expect(VideoUiStrings.seeMore, 'Voir plus');
    expect(VideoUiStrings.likeVideo, 'Aimer la vidéo');
    expect(VideoUiStrings.deleteVideoSemantic, 'Supprimer la vidéo');
    expect(VideoUiStrings.videoNotFound, 'Vidéo introuvable.');
    expect(VideoUiStrings.likeAdded, 'Mention J’aime ajoutée.');
    expect(VideoUiStrings.feedEndTitle, 'Vous êtes à jour');
    expect(
      VideoUiStrings.feedEndMessage(1),
      contains('la seule vidéo disponible'),
    );
    expect(VideoUiStrings.feedEndMessage(3), contains('les 3 vidéos'));
    expect(VideoUiStrings.videoStateProcessing, 'Traitement…');
    expect(
      VideoUiStrings.videoNotPlayableFailed,
      'Le traitement de cette vidéo a échoué. Supprimez-la et réessayez.',
    );
    expect(VideoUiStrings.uploadSuccess, 'Vidéo prête et visible.');
    expect(VideoUiStrings.uploadFileTooLarge, contains('150 Mo'));
    expect(
      VideoUiStrings.uploadOptimizationFailed('failed'),
      'Échec d’optimisation vidéo (statut : failed). Merci de réessayer.',
    );
    expect(VideoUiStrings.uploadStepPrepare, 'Préparation');
    expect(VideoUiStrings.uploadStageUploadingVideo, 'Téléversement vidéo...');
    expect(VideoUiStrings.likeCountValue(1), '1 mention J’aime');
    expect(VideoUiStrings.likeCountValue(4), '4 mentions J’aime');
    expect(VideoUiStrings.shareCountValue(2), '2 partages');
    expect(VideoUiStrings.uploadTrimmed(3), 'Vidéo préparée en extrait de 3s.');
    expect('profileLevelElite'.tr, 'Profil Élite');
    expect('profileTrustVerified'.tr, 'Vérifié par Adfoot');
    expect('authErrorWrongPassword'.tr, 'Mot de passe incorrect.');
    expect('authErrorUserNotFound'.tr, contains('Ce compte est introuvable'));
    expect('publicSignupDisabledMessage'.tr, contains('équipe Adfoot'));
    expect(
      'sessionNoLongerAuthorizedMessage'.tr,
      'Votre session n’est plus autorisée.',
    );
    expect('accountDisabledTitle'.tr, 'Compte désactivé');
    expect(
      'profileLoadFailedMessage'.tr,
      contains('Réessayez dans quelques instants'),
    );
    expect('chatEmptyMessageError'.tr, 'Le message est vide.');
    expect(
      'sessionClosedReconnectMessage'.tr,
      'Votre session a été fermée. Veuillez vous reconnecter.',
    );
    expect(
      'eventUpdateSuccessMessage'.tr,
      'Les modifications ont été enregistrées.',
    );
    expect(
      'eventNewNotificationBody'.trParams({'name': 'Awa', 'title': 'U17'}),
      'Awa a créé un nouvel événement : U17',
    );
    expect(
      'offreUpdateSuccessMessage'.tr,
      'Les modifications ont été enregistrées.',
    );
    expect(
      'offreStatusUpdatedMessage'.trParams({'status': 'active'}),
      'Le statut est maintenant "active".',
    );
    expect('offreDeleteSuccessMessage'.tr, 'Offre supprimée avec succès.');
    expect(
      'offreApplyPlayersOnlyMessage'.tr,
      'Seuls les joueurs peuvent postuler à une offre.',
    );
    expect('profileUnavailableTitle'.tr, 'Profil indisponible');
    expect('profileNotFoundMessage'.tr, 'Profil introuvable.');
    expect(
      'profileLoadConnectionUnstableMessage'.tr,
      'Connexion instable. Vérifiez votre réseau puis réessayez.',
    );
    expect(
      'profileWriteAppCheckDeniedMessage'.trParams({'code': 'x/y'}),
      contains('Code: x/y'),
    );
    expect('profileCvSavedMessage'.tr, 'Votre CV a été ajouté ou mis à jour.');
    expect('actionResponseDefaultSuccessMessage'.tr, 'Action réalisée.');
    expect(
      'actionResponseOfflineMessage'.tr,
      'Connexion indisponible. Réessaie quand tu es en ligne.',
    );
    expect('contactContextOfferLabel'.tr, 'Offre');
    expect('contactReasonOpportunityLabel'.tr, 'Opportunité');
    expect('agencyFollowUpQualifiedLabel'.tr, 'Qualifié');
    expect(
      'chatGuidedFirstContactReasonPart'.trParams({'reason': 'Suivi'}),
      'Motif : Suivi.',
    );
  });

  testWidgets('English resolves to real translations, not the French '
      'fallback', (tester) async {
    await pumpWithLocale(tester, const Locale('en'));

    expect(VideoUiStrings.retry, 'Retry');
    expect(VideoUiStrings.noInternetTitle, 'No internet connection');
    expect(VideoUiStrings.videoSearchIdleLabel, 'Position, player, club');
    expect(VideoUiStrings.pendingVideosLabel(1), '1 new video');
    expect(VideoUiStrings.pendingVideosLabel(3), '3 new videos');
    expect(VideoUiStrings.pendingVideosSemantic(1), '1 new video available');
    expect(VideoUiStrings.pendingVideosSemantic(5), '5 new videos available');
    expect(VideoUiStrings.videoSearchOpen, 'Search');
    expect(VideoUiStrings.videoSearchHint, 'Position, player, club...');
    expect(VideoUiStrings.defaultPublisherName, 'Adfoot Profile');
    expect(VideoUiStrings.videoSearchResultHint, 'Open this video');
    expect(VideoUiStrings.back, 'Back');
    expect(VideoUiStrings.emptyProfileVideoFeedTitle, 'No videos to show');
    expect(VideoUiStrings.uploadFormTitle, 'Submit a video');
    expect(VideoUiStrings.uploadFormSubtitle, 'Preview and details');
    expect(VideoUiStrings.descriptionLabel, 'Description (required)');
    expect(VideoUiStrings.captionLabel, 'Caption (required)');
    expect(VideoUiStrings.discardDraftTitle, 'Discard this video?');
    expect(VideoUiStrings.discardDraftConfirm, 'Discard');
    expect(
      VideoUiStrings.unexpectedUploadError('network error'),
      'Unexpected error: network error',
    );
    expect(VideoUiStrings.addVideoScreenTitle, 'Add a video');
    expect(VideoUiStrings.chooseFromGallery, 'Choose from gallery');
    expect(
      VideoUiStrings.uploadQuotaReachedMessage(10),
      'Your account has reached its limit of 10 published videos. '
      'To publish more, ask the Adfoot agency to raise your limit.',
    );
    expect(
      VideoUiStrings.uploadQuotaContactFallback(
        '+225 00 00 00 00',
        'adfoot.org',
      ),
      'Message the Adfoot agency on WhatsApp at +225 00 00 00 00, or go '
      'through adfoot.org, to raise your video limit.',
    );
    expect(VideoUiStrings.loadingMessage, 'Loading the video...');
    expect(VideoUiStrings.playbackErrorTitle, 'Playback failed');
    expect(VideoUiStrings.playVideo, 'Play the video');
    expect(VideoUiStrings.rewindTenSecondsFeedback, '-10s');
    expect(VideoUiStrings.playbackSpeed, 'Playback speed');
    expect(VideoUiStrings.videoCaptionSheetTitle, 'Caption');
    expect(VideoUiStrings.seeMore, 'See more');
    expect(VideoUiStrings.likeVideo, 'Like the video');
    expect(VideoUiStrings.deleteVideoSemantic, 'Delete the video');
    expect(VideoUiStrings.videoNotFound, 'Video not found.');
    expect(VideoUiStrings.likeAdded, 'Like added.');
    expect(VideoUiStrings.feedEndTitle, 'You are up to date');
    expect(
      VideoUiStrings.feedEndMessage(1),
      contains('the only available video'),
    );
    expect(VideoUiStrings.feedEndMessage(3), contains('all 3 available'));
    expect(VideoUiStrings.videoStateProcessing, 'Processing…');
    expect(
      VideoUiStrings.videoNotPlayableFailed,
      'Processing this video failed. Delete it and try again.',
    );
    expect(VideoUiStrings.uploadSuccess, 'Video ready and visible.');
    expect(VideoUiStrings.uploadFileTooLarge, contains('150 MB'));
    expect(
      VideoUiStrings.uploadOptimizationFailed('failed'),
      'Video optimization failed (status: failed). Please try again.',
    );
    expect(VideoUiStrings.uploadStepPrepare, 'Prepare');
    expect(VideoUiStrings.uploadStageUploadingVideo, 'Uploading video...');
    expect(VideoUiStrings.likeCountValue(1), '1 like');
    expect(VideoUiStrings.likeCountValue(4), '4 likes');
    expect(VideoUiStrings.shareCountValue(2), '2 shares');
    expect(
      VideoUiStrings.uploadTrimmed(3),
      'Video trimmed to a 3-second clip.',
    );
    expect('profileLevelElite'.tr, 'Elite Profile');
    expect('profileTrustVerified'.tr, 'Verified by Adfoot');
    expect('authErrorWrongPassword'.tr, 'Incorrect password.');
    expect(
      'authErrorUserNotFound'.tr,
      contains('This account could not be found'),
    );
    expect('publicSignupDisabledMessage'.tr, contains('Adfoot team'));
    expect(
      'sessionNoLongerAuthorizedMessage'.tr,
      'Your session is no longer authorized.',
    );
    expect('accountDisabledTitle'.tr, 'Account disabled');
    expect('profileLoadFailedMessage'.tr, contains('Try again in a moment'));
    expect('chatEmptyMessageError'.tr, 'The message is empty.');
    expect(
      'sessionClosedReconnectMessage'.tr,
      'Your session was closed. Please sign in again.',
    );
    expect('eventUpdateSuccessMessage'.tr, 'Your changes have been saved.');
    expect(
      'eventNewNotificationBody'.trParams({'name': 'Awa', 'title': 'U17'}),
      'Awa created a new event: U17',
    );
    expect('offreUpdateSuccessMessage'.tr, 'Your changes have been saved.');
    expect(
      'offreStatusUpdatedMessage'.trParams({'status': 'active'}),
      'The status is now "active".',
    );
    expect('offreDeleteSuccessMessage'.tr, 'Offer deleted successfully.');
    expect(
      'offreApplyPlayersOnlyMessage'.tr,
      'Only players can apply to an offer.',
    );
    expect('profileUnavailableTitle'.tr, 'Profile unavailable');
    expect('profileNotFoundMessage'.tr, 'Profile not found.');
    expect(
      'profileLoadConnectionUnstableMessage'.tr,
      'Unstable connection. Check your network, then try again.',
    );
    expect(
      'profileWriteAppCheckDeniedMessage'.trParams({'code': 'x/y'}),
      contains('Code: x/y'),
    );
    expect('profileCvSavedMessage'.tr, 'Your CV has been added or updated.');
    expect('actionResponseDefaultSuccessMessage'.tr, 'Action completed.');
    expect(
      'actionResponseOfflineMessage'.tr,
      'No connection available. Try again once you\'re back online.',
    );
    expect('contactContextOfferLabel'.tr, 'Offer');
    expect('contactReasonOpportunityLabel'.tr, 'Opportunity');
    expect('agencyFollowUpQualifiedLabel'.tr, 'Qualified');
    expect(
      'chatGuidedFirstContactReasonPart'.trParams({'reason': 'Follow-up'}),
      'Reason: Follow-up.',
    );
  });
}
