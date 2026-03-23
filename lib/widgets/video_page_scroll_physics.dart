import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

class VideoPageScrollPhysics extends PageScrollPhysics {
  const VideoPageScrollPhysics({super.parent});

  static const double _dragMultiplier = 1.28;
  static const double _momentumFactor = 0.12;
  static const double _maxCarriedMomentum = 2200.0;
  static const double _pageFlipThreshold = 0.14;
  static const double _pageDecisionVelocity = 80.0;
  static const SpringDescription _snapSpring = SpringDescription(
    mass: 0.9,
    stiffness: 260.0,
    damping: 28.0,
  );

  @override
  VideoPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return VideoPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 10.0;

  @override
  double get minFlingVelocity => 140.0;

  @override
  double get maxFlingVelocity => 12000.0;

  @override
  double get dragStartDistanceMotionThreshold => 1.0;

  @override
  SpringDescription get spring => _snapSpring;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset) * _dragMultiplier;
  }

  @override
  double carriedMomentum(double existingVelocity) {
    final carried = existingVelocity * _momentumFactor;
    return carried.sign * math.min(carried.abs(), _maxCarriedMomentum);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final tolerance = toleranceFor(position);
    final targetPixels = targetPixelsForTests(
      position: position,
      velocity: velocity,
      tolerance: tolerance,
    );

    if ((targetPixels - position.pixels).abs() <= tolerance.distance) {
      return null;
    }

    return ScrollSpringSimulation(
      spring,
      position.pixels,
      targetPixels,
      velocity,
      tolerance: tolerance,
    );
  }

  @visibleForTesting
  double targetPixelsForTests({
    required ScrollMetrics position,
    required double velocity,
    Tolerance? tolerance,
  }) {
    final targetPage = targetPageForTests(
      position: position,
      velocity: velocity,
      tolerance: tolerance,
    );
    final targetPixels = _getPixels(position, targetPage);
    return targetPixels.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  @visibleForTesting
  double targetPageForTests({
    required ScrollMetrics position,
    required double velocity,
    Tolerance? tolerance,
  }) {
    final resolvedTolerance = tolerance ?? toleranceFor(position);
    final currentPage = _getPage(position);
    final floorPage = currentPage.floorToDouble();
    final ceilPage = currentPage.ceilToDouble();
    final pageFraction = currentPage - floorPage;
    final absVelocity = velocity.abs();

    if (absVelocity >= resolvedTolerance.velocity) {
      return velocity > 0.0 ? ceilPage : floorPage;
    }

    if (absVelocity >= _pageDecisionVelocity) {
      if (velocity > 0.0 && pageFraction >= _pageFlipThreshold) {
        return ceilPage;
      }
      if (velocity < 0.0 && pageFraction <= 1.0 - _pageFlipThreshold) {
        return floorPage;
      }
    }

    return currentPage.roundToDouble();
  }

  double _getPage(ScrollMetrics position) {
    if (position is PageMetrics) {
      return position.page ?? 0.0;
    }

    final viewport = position.viewportDimension;
    if (viewport == 0.0) {
      return 0.0;
    }
    return position.pixels / viewport;
  }

  double _getPixels(ScrollMetrics position, double page) {
    if (position is PageMetrics) {
      return page * position.viewportDimension * position.viewportFraction;
    }

    return page * position.viewportDimension;
  }
}
