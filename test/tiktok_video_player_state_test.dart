import 'package:adfoot/widgets/tiktok_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          height: 720,
          child: child,
        ),
      ),
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

  testWidgets('shows a retry state when playback has no usable controller',
      (tester) async {
    var retried = false;

    await tester.pumpWidget(
      host(
        player(
          errorMessage: 'Lecture vidéo indisponible.',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Lecture vidéo indisponible.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    expect(retried, isTrue);
  });

  testWidgets('keeps the thumbnail visible while loading', (tester) async {
    await tester.pumpWidget(host(player(isLoading: true)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Préparation de la vidéo...'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });
}
