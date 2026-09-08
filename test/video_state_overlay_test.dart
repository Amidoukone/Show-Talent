import 'package:adfoot/l10n/video_ui_translations.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/video_state_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  // Set directly (not via a pumped GetMaterialApp) so `.tr` already resolves
  // to real French text the moment a test body starts running -- several
  // tests below evaluate a `VideoUiStrings`/`VideoStateOverlay` getter as a
  // widget constructor argument, which is built *before* `pumpWidget` runs;
  // a GetMaterialApp only registers its translations once it is actually
  // mounted, which would be too late for that eager evaluation and would
  // silently freeze the bare translation key instead -- see
  // [[project_adfoot_i18n_ios_effort]].
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

  testWidgets('loading overlay keeps the standard loading message', (
    tester,
  ) async {
    await tester.pumpWidget(host(const VideoStateOverlay.loading()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(VideoUiStrings.loadingMessage), findsOneWidget);
    expect(find.text(VideoUiStrings.retry), findsNothing);
  });

  testWidgets('slow loading overlay can expose a retry action', (tester) async {
    var retried = false;

    await tester.pumpWidget(
      host(
        VideoStateOverlay.loading(
          message: VideoStateOverlay.slowLoadingMessage,
          showRetry: true,
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text(VideoUiStrings.slowLoadingMessage), findsOneWidget);
    expect(find.text(VideoUiStrings.slowLoadingDetail), findsOneWidget);
    expect(find.text(VideoUiStrings.retry), findsOneWidget);

    await tester.tap(find.text(VideoUiStrings.retry));
    expect(retried, isTrue);
  });

  testWidgets('error overlay uses fallback text and retry action', (
    tester,
  ) async {
    var retried = false;

    await tester.pumpWidget(
      host(VideoStateOverlay.error(onRetry: () => retried = true)),
    );

    expect(find.text(VideoUiStrings.playbackErrorTitle), findsOneWidget);
    expect(find.text(VideoUiStrings.playbackUnavailable), findsOneWidget);
    expect(find.text(VideoUiStrings.retry), findsOneWidget);

    await tester.tap(find.text(VideoUiStrings.retry));
    expect(retried, isTrue);
  });

  testWidgets('error overlay hides technical player messages', (tester) async {
    await tester.pumpWidget(
      host(
        const VideoStateOverlay.error(
          message: 'Exception: source error https://storage.example/video.mp4',
        ),
      ),
    );

    expect(find.text(VideoUiStrings.playbackUnavailable), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });
}
