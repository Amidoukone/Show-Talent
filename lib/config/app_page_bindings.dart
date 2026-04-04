import 'package:get/get.dart';

import '../controller/chat_controller.dart';
import '../controller/event_controller.dart';

class MainShellBinding extends Bindings {
  @override
  void dependencies() {
    _registerRouteScoped<ChatController>(() => ChatController());
    _registerRouteScoped<EventController>(() => EventController());
  }

  void _registerRouteScoped<T>(T Function() builder) {
    if (Get.isRegistered<T>() || Get.isPrepared<T>()) {
      return;
    }

    Get.lazyPut<T>(builder);
  }
}
