import 'package:flutter/foundation.dart' show visibleForTesting;
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

  // Exactly the hazard documented above for ProfileController, and it was
  // left unguarded here even though the video contexts are *more* exposed to
  // it: opening a video from a profile grid means ProfileScreen and
  // ProfileVideoScrollView both hold the same `profile:<uid>` context at the
  // same time, each with its own ensure/release pair. Without counting, the
  // first release tore down the shared controller -- cancelling its Firestore
  // subscription and disposing every player VideoManager held for that
  // context -- while the screen underneath was still using it.
  //
  // Today that happens to be survivable only because of the order the two
  // releases run in: the scroll view pops first and the profile screen's
  // release then finds nothing left to delete. Pushing the same profile twice
  // is enough to reverse that order, and nothing in the code says it may not
  // happen.
  static final Map<String, int> _videoControllerRefCounts = {};

  static VideoController ensureVideoController({
    required String contextKey,
    required bool enableLiveStream,
    required bool enableFeedFetch,
    bool permanent = true,
  }) {
    _videoControllerRefCounts[contextKey] =
        (_videoControllerRefCounts[contextKey] ?? 0) + 1;

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
    final remaining = (_videoControllerRefCounts[contextKey] ?? 1) - 1;
    if (remaining > 0) {
      _videoControllerRefCounts[contextKey] = remaining;
      return;
    }
    _videoControllerRefCounts.remove(contextKey);

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

  @visibleForTesting
  static int videoControllerRefCount(String contextKey) =>
      _videoControllerRefCounts[contextKey] ?? 0;

  @visibleForTesting
  static void resetVideoControllerRefCountsForTests() {
    _videoControllerRefCounts.clear();
  }

  static UploadVideoController ensureUploadVideoController() {
    if (Get.isRegistered<UploadVideoController>()) {
      return Get.find<UploadVideoController>();
    }

    return Get.put(UploadVideoController(), permanent: false);
  }
}
