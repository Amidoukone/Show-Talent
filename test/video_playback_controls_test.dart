import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/video_playback_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {double height = 120}) {
    return MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(width: 400, height: height, child: child),
      ),
    );
  }

  testWidgets('playback controls expose stable labels and callbacks', (
    tester,
  ) async {
    var rewind = 0;
    var toggle = 0;
    var forward = 0;
    var speed = 0;

    await tester.pumpWidget(
      host(
        VideoPlaybackControls(
          isPlaying: false,
          onReplay10: () => rewind++,
          onTogglePlayPause: () => toggle++,
          onForward10: () => forward++,
          onSpeed: () => speed++,
        ),
      ),
    );

    expect(find.byTooltip(VideoUiStrings.rewindTenSeconds), findsOneWidget);
    expect(find.byTooltip(VideoUiStrings.playVideo), findsOneWidget);
    expect(find.byTooltip(VideoUiStrings.forwardTenSeconds), findsOneWidget);
    expect(find.byTooltip(VideoUiStrings.playbackSpeed), findsOneWidget);

    await tester.tap(find.byTooltip(VideoUiStrings.rewindTenSeconds));
    await tester.tap(find.byTooltip(VideoUiStrings.playVideo));
    await tester.tap(find.byTooltip(VideoUiStrings.forwardTenSeconds));
    await tester.tap(find.byTooltip(VideoUiStrings.playbackSpeed));

    expect(rewind, 1);
    expect(toggle, 1);
    expect(forward, 1);
    expect(speed, 1);
  });

  testWidgets('progress bar displays time and maps taps to seek proportion', (
    tester,
  ) async {
    double? tappedProportion;

    await tester.pumpWidget(
      host(
        VideoProgressBar(
          position: const Duration(seconds: 15),
          duration: const Duration(minutes: 1),
          isDragging: false,
          dragProgress: 0,
          onDragStart: () {},
          onDragUpdate: (_) {},
          onDragEnd: () {},
          onTapSeek: (proportion) => tappedProportion = proportion,
        ),
      ),
    );

    expect(find.text('00:15'), findsOneWidget);
    expect(find.text('01:00'), findsOneWidget);

    final trackFinder = find.descendant(
      of: find.byType(VideoProgressBar),
      matching: find.byType(GestureDetector),
    );
    await tester.tapAt(tester.getRect(trackFinder).center);

    expect(tappedProportion, isNotNull);
    expect(tappedProportion!, closeTo(0.5, 0.02));
  });

  testWidgets('speed sheet highlights current speed and returns a selection', (
    tester,
  ) async {
    double? selectedSpeed;

    await tester.pumpWidget(
      host(
        VideoPlaybackSpeedSheet(
          selectedSpeed: 1.0,
          onSpeedSelected: (speed) => selectedSpeed = speed,
        ),
        height: 420,
      ),
    );

    expect(find.text(VideoUiStrings.playbackSpeed), findsOneWidget);
    expect(find.text('1x'), findsWidgets);
    expect(find.text('1.5x'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    final option = find.ancestor(
      of: find.text('1.5x'),
      matching: find.byType(InkWell),
    );
    await tester.tap(option);

    expect(selectedSpeed, 1.5);
  });
}
