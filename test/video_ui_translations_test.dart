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

  testWidgets('French resolves to real copy, not the bare key', (
    tester,
  ) async {
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
  });

  testWidgets('English resolves to real translations, not the French '
      'fallback', (tester) async {
    await pumpWithLocale(tester, const Locale('en'));

    expect(VideoUiStrings.retry, 'Retry');
    expect(VideoUiStrings.noInternetTitle, 'No internet connection');
    expect(VideoUiStrings.videoSearchIdleLabel, 'Position, player, club');
    expect(VideoUiStrings.pendingVideosLabel(1), '1 new video');
    expect(VideoUiStrings.pendingVideosLabel(3), '3 new videos');
    expect(
      VideoUiStrings.pendingVideosSemantic(1),
      '1 new video available',
    );
    expect(
      VideoUiStrings.pendingVideosSemantic(5),
      '5 new videos available',
    );
    expect(VideoUiStrings.videoSearchOpen, 'Search');
    expect(VideoUiStrings.videoSearchHint, 'Position, player, club...');
    expect(VideoUiStrings.defaultPublisherName, 'Adfoot Profile');
    expect(VideoUiStrings.videoSearchResultHint, 'Open this video');
  });
}
