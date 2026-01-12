import 'package:flutter/widgets.dart';

class VideoPageScrollPhysics extends PageScrollPhysics {
  const VideoPageScrollPhysics({super.parent});

  @override
  VideoPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return VideoPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingVelocity => 250.0;

  @override
  double get dragStartDistanceMotionThreshold => 2.0;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset) * 1.1;
  }
}
