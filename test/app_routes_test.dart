import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/config/app_routes.dart';
import 'package:get/get.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(Get.reset);

  test('AppRoutes exposes the core route table in one place', () {
    final routeNames = AppRoutes.pages.map((page) => page.name).toList();

    expect(
      routeNames,
      equals(<String>[
        AppRoutes.splash,
        AppRoutes.login,
        AppRoutes.main,
        AppRoutes.verifyEmail,
        AppRoutes.resetPassword,
      ]),
    );
  });

  test('Main route declares shell bindings for chat and events', () {
    final mainPage =
        AppRoutes.pages.firstWhere((page) => page.name == AppRoutes.main);

    mainPage.binding?.dependencies();

    expect(Get.isPrepared<ChatController>(), isTrue);
    expect(Get.isPrepared<EventController>(), isTrue);
  });
}
