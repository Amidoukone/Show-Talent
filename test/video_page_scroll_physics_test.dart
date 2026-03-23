import 'package:adfoot/widgets/video_page_scroll_physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final metrics = FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 300,
    pixels: 100,
    viewportDimension: 100,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 1,
  );

  test('video page scroll physics is tuned for short and reactive swipes', () {
    const physics = VideoPageScrollPhysics();

    expect(physics.minFlingDistance, 10);
    expect(physics.minFlingVelocity, 140);
    expect(physics.maxFlingVelocity, 12000);
    expect(physics.dragStartDistanceMotionThreshold, 1);
  });

  test('video page scroll physics amplifies drag movement', () {
    const physics = VideoPageScrollPhysics();

    expect(
      physics.applyPhysicsToUserOffset(metrics, 100),
      closeTo(128, 0.001),
    );
  });

  test('video page scroll physics keeps some momentum for chained swipes', () {
    const physics = VideoPageScrollPhysics();

    expect(
      physics.carriedMomentum(4000),
      closeTo(480, 0.001),
    );
    expect(
      physics.carriedMomentum(30000),
      closeTo(2200, 0.001),
    );
  });

  test('video page scroll physics flips early when swipe intent is clear', () {
    const physics = VideoPageScrollPhysics();

    final forwardMetrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 400,
      pixels: 118,
      viewportDimension: 100,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    final backwardMetrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 400,
      pixels: 182,
      viewportDimension: 100,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    expect(
      physics.targetPageForTests(
        position: forwardMetrics,
        velocity: 90,
      ),
      2,
    );
    expect(
      physics.targetPageForTests(
        position: backwardMetrics,
        velocity: -90,
      ),
      1,
    );
  });

  test('video page scroll physics stays on the current page for tiny drags',
      () {
    const physics = VideoPageScrollPhysics();

    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 400,
      pixels: 109,
      viewportDimension: 100,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    expect(
      physics.targetPageForTests(
        position: metrics,
        velocity: 90,
      ),
      1,
    );
    expect(
      physics.targetPixelsForTests(
        position: metrics,
        velocity: 90,
      ),
      100,
    );
  });
}
