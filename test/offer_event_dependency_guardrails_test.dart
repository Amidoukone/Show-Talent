import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offer and event controllers are registered before screen lookup', () {
    final appBindings = File('lib/config/app_bindings.dart').readAsStringSync();
    final offerScreen =
        File('lib/screens/offre_screen.dart').readAsStringSync();
    final eventListScreen =
        File('lib/screens/event_list_screen.dart').readAsStringSync();

    expect(offerScreen, contains('Get.find<OffreController>()'));
    expect(eventListScreen, contains('Get.find<EventController>()'));
    expect(
      appBindings,
      contains("import '../controller/event_controller.dart';"),
    );
    expect(
      appBindings,
      contains("import '../controller/offre_controller.dart';"),
    );
    expect(
      appBindings,
      contains('_registerPermanent<EventController>(() => EventController())'),
    );
    expect(
      appBindings,
      contains('_registerPermanent<OffreController>(() => OffreController())'),
    );
  });
}
