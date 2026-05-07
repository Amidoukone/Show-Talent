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
}
