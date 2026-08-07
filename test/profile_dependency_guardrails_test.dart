import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile chat dependency is registered before route-specific screens',
      () {
    final appBindings = File('lib/config/app_bindings.dart').readAsStringSync();
    final profileScreen =
        File('lib/screens/profile_screen.dart').readAsStringSync();

    expect(profileScreen, contains('Get.find<ChatController>()'));
    expect(
        appBindings, contains("import '../controller/chat_controller.dart';"));
    expect(
      appBindings,
      contains('_registerPermanent<ChatController>(() => ChatController())'),
    );
  });

  test('profile video feed ensures its tagged controller before lookup', () {
    final registry =
        File('lib/config/feature_controller_registry.dart').readAsStringSync();
    final feed =
        File('lib/screens/profile_video_feed_screen.dart').readAsStringSync();

    expect(
        registry, contains('static ProfileController ensureProfileController'));
    expect(
        feed,
        contains(
            'FeatureControllerRegistry.ensureProfileController(widget.uid)'));
    expect(
        feed, isNot(contains('Get.find<ProfileController>(tag: widget.uid)')));
  });
}
