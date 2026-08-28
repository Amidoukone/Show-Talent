import 'dart:async';

import 'package:get/get.dart';

import '../controller/auth_controller.dart';
import '../controller/chat_controller.dart';
import '../controller/event_controller.dart';
import '../controller/follow_controller.dart';
import '../controller/offre_controller.dart';
import '../controller/user_controller.dart';
import '../services/video_metrics_observer.dart';
import '../videos/domain/video_lifecycle_observer.dart';
import '../videos/video_manager.dart';

class AppBindings {
  AppBindings._();

  /// Kept alive for the life of the process, like the manager it feeds.
  static VideoLifecycleObserver? _videoLifecycleObserver;

  static void registerPermanentDependencies() {
    final videoManager = _registerPermanent<VideoManager>(() => VideoManager());
    videoManager.onMetrics =
        VideoMetricsObserver(videoManager: videoManager).handle;

    // Registered here rather than by a screen, because what kept playing in
    // the background was never a screen's controller: it was an
    // initialisation still in flight inside the manager. See
    // [VideoLifecycleObserver].
    _videoLifecycleObserver ??= VideoLifecycleObserver(
      videoManager: videoManager,
    )..start();

    _registerPermanent<AuthController>(() => AuthController());
    _registerPermanent<UserController>(() => UserController());
    _registerPermanent<FollowController>(() => FollowController());
    _registerPermanent<ChatController>(() => ChatController());
    _registerPermanent<EventController>(() => EventController());
    _registerPermanent<OffreController>(() => OffreController());
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
