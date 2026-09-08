import 'package:adfoot/l10n/video_ui_translations.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/tiktok_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  // Set directly (not via a pumped GetMaterialApp) so `.tr` already resolves
  // to real French text the moment a test body starts running -- the test
  // below evaluates `VideoUiStrings.playbackUnavailable` as a widget
  // constructor argument, which is built *before* `pumpWidget` runs; a
  // GetMaterialApp only registers its translations once it is actually
  // mounted, which would be too late and would silently freeze the bare
  // translation key instead -- see [[project_adfoot_i18n_ios_effort]].
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(VideoUiTranslations().keys);
    Get.locale = const Locale('fr');
    Get.fallbackLocale = const Locale('fr');
  });
  tearDown(() {
    Get.clearTranslations();
    Get.reset();
  });

  Widget host(Widget child) {
    return MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(body: SizedBox(width: 390, height: 720, child: child)),
    );
  }

  TiktokVideoPlayer player({
    bool isLoading = false,
    String? errorMessage,
    VoidCallback? onRetry,
  }) {
    return TiktokVideoPlayer(
      controller: null,
      isPlaying: false,
      hidePlayPauseIcon: true,
      showControls: true,
      showProgressBar: false,
      isBuffering: false,
      isLoading: isLoading,
      errorMessage: errorMessage,
      thumbnailUrl: '',
      hasFirstFrame: false,
      onRetry: onRetry,
    );
  }

  testWidgets('shows a retry state when playback has no usable controller', (
    tester,
  ) async {
    var retried = false;

    await tester.pumpWidget(
      host(
        player(
          errorMessage: VideoUiStrings.playbackUnavailable,
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text(VideoUiStrings.playbackErrorTitle), findsOneWidget);
    expect(find.text(VideoUiStrings.playbackUnavailable), findsOneWidget);
    expect(find.text(VideoUiStrings.retry), findsOneWidget);

    await tester.tap(find.text(VideoUiStrings.retry));
    expect(retried, isTrue);
  });

  testWidgets('keeps the thumbnail visible while loading', (tester) async {
    await tester.pumpWidget(host(player(isLoading: true)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(VideoUiStrings.loadingMessage), findsOneWidget);
    expect(find.text(VideoUiStrings.retry), findsNothing);
  });
}
