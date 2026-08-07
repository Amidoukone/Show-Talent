import 'package:get/get.dart';

import '../controller/profile_controller.dart';
import '../controller/upload_video_controller.dart';
import '../controller/video_controller.dart';

class FeatureControllerRegistry {
  FeatureControllerRegistry._();

  static ProfileController ensureProfileController(String uid) {
    if (Get.isRegistered<ProfileController>(tag: uid)) {
      return Get.find<ProfileController>(tag: uid);
    }

    return Get.put(ProfileController(), tag: uid);
  }

  static void releaseProfileController(String uid) {
    if (!Get.isRegistered<ProfileController>(tag: uid)) {
      return;
    }
    Get.delete<ProfileController>(tag: uid);
  }

  static VideoController ensureVideoController({
    required String contextKey,
    required bool enableLiveStream,
    required bool enableFeedFetch,
    bool permanent = true,
  }) {
    if (Get.isRegistered<VideoController>(tag: contextKey)) {
      return Get.find<VideoController>(tag: contextKey);
    }

    return Get.put(
      VideoController(
        contextKey: contextKey,
        enableLiveStream: enableLiveStream,
        enableFeedFetch: enableFeedFetch,
      ),
      tag: contextKey,
      permanent: permanent,
    );
  }

  static VideoController findVideoController(String contextKey) {
    return Get.find<VideoController>(tag: contextKey);
  }

  static void releaseVideoController(String contextKey) {
    if (!Get.isRegistered<VideoController>(tag: contextKey)) {
      return;
    }
    Get.delete<VideoController>(tag: contextKey);
  }

  static UploadVideoController ensureUploadVideoController() {
    if (Get.isRegistered<UploadVideoController>()) {
      return Get.find<UploadVideoController>();
    }

    return Get.put(UploadVideoController(), permanent: false);
  }
}
