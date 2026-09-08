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
  });
}
