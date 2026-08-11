import 'package:get/get.dart';

import '../controller/profile_controller.dart';
import '../controller/upload_video_controller.dart';
import '../controller/video_controller.dart';

class FeatureControllerRegistry {
  FeatureControllerRegistry._();

  // ProfileScreen can legitimately be pushed twice for the same uid in the
  // same nav stack (e.g. tapping your own avatar from a video card while a
  // "My profile" tab for the same uid is already mounted underneath). Both
  // instances share the single ProfileController registered under that
  // uid. Without ref-counting, popping the top instance called
  // Get.delete unconditionally, tearing down the shared controller (its
  // Firestore listener, its VideoManager-cached players) while the screen
  // still visible below kept a live GetBuilder reference to it -- it would
  // silently stop receiving profile updates.
  static final Map<String, int> _profileControllerRefCounts = {};

  static ProfileController ensureProfileController(String uid) {
    _profileControllerRefCounts[uid] =
        (_profileControllerRefCounts[uid] ?? 0) + 1;

    if (Get.isRegistered<ProfileController>(tag: uid)) {
      return Get.find<ProfileController>(tag: uid);
    }

    return Get.put(ProfileController(), tag: uid);
  }

  static void releaseProfileController(String uid) {
    final remaining = (_profileControllerRefCounts[uid] ?? 1) - 1;
    if (remaining > 0) {
      _profileControllerRefCounts[uid] = remaining;
      return;
    }
    _profileControllerRefCounts.remove(uid);

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
    // ensureVideoController registers with permanent: true (the default,
    // and every call site passes it explicitly). GetX's delete() silently
    // refuses to remove a permanent instance unless force: true is passed
    // -- without it, onClose() never fires and every unique contextKey
    // (e.g. one per profile visited) stays registered for the app's
    // lifetime.
    Get.delete<VideoController>(tag: contextKey, force: true);
  }

  static UploadVideoController ensureUploadVideoController() {
    if (Get.isRegistered<UploadVideoController>()) {
      return Get.find<UploadVideoController>();
    }

    return Get.put(UploadVideoController(), permanent: false);
  }
}
