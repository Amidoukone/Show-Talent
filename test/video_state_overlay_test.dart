import 'package:adfoot/widgets/video_state_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 390, height: 720, child: child),
      ),
    );
  }

  testWidgets('loading overlay keeps the standard loading message',
      (tester) async {
    await tester.pumpWidget(
      host(const VideoStateOverlay.loading()),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Chargement de la vidéo...'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
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

    expect(find.text('Connexion lente...'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    expect(retried, isTrue);
  });

  testWidgets('error overlay uses fallback text and retry action',
      (tester) async {
    var retried = false;

    await tester.pumpWidget(
      host(VideoStateOverlay.error(onRetry: () => retried = true)),
    );

    expect(find.text('Lecture vidéo indisponible.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    expect(retried, isTrue);
  });
}
