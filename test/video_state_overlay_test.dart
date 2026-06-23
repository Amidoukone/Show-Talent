import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/video_state_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
