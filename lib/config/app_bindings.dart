import 'dart:async';

import 'package:get/get.dart';

import '../controller/auth_controller.dart';
import '../controller/follow_controller.dart';
import '../controller/user_controller.dart';
import '../services/video_metrics_observer.dart';
import '../widgets/video_manager.dart';

class AppBindings {
  AppBindings._();

  static void registerPermanentDependencies() {
    final videoManager = _registerPermanent<VideoManager>(() => VideoManager());
    videoManager.onMetrics =
        VideoMetricsObserver(videoManager: videoManager).handle;

    _registerPermanent<AuthController>(() => AuthController());
    _registerPermanent<UserController>(() => UserController());
    _registerPermanent<FollowController>(() => FollowController());
  }

  static void warmUpBackgroundServices() {
    if (!Get.isRegistered<VideoManager>()) {
      return;
    }

    unawaited(Get.find<VideoManager>().warmNetworkProfile());
  }

  static T _registerPermanent<T>(T Function() builder) {
    if (Get.isRegistered<T>()) {
      return Get.find<T>();
    }

    return Get.put<T>(builder(), permanent: true);
  }
}
