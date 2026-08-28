import 'package:get/get.dart';

import '../controller/chat_controller.dart';
import '../controller/event_controller.dart';
import '../controller/offre_controller.dart';

/// A safety net for `/main`, and nothing more.
///
/// Worth being exact about, because the comment that used to sit here was
/// not: it described these three controllers as route-scoped, deleted by GetX
/// when `/main` is replaced, and lost for the rest of the session.
///
/// None of that happens, and this binding does not prevent it. `AppBootstrap`
/// calls `AppBindings.registerPermanentDependencies()` before `runApp`, which
/// does `Get.put(..., permanent: true)` for all three — so by the time this
/// route is ever built, `Get.isRegistered` is already true for each and every
/// call below returns at the guard. GetX does not delete a permanent instance
/// when a route is removed, which is precisely why the tabs do not in fact go
/// empty when session routing replaces `/main` with itself.
///
/// So this registers nothing today. It is kept, rather than deleted, as cover
/// for the one case that would otherwise be fatal: bootstrap being reordered
/// or failing before that call, leaving `/main` to be built with no
/// controllers at all. `fenix` is right for that path — a lazily built
/// instance is route-scoped, and without it a disposal would be permanent.
class MainShellBinding extends Bindings {
  @override
  void dependencies() {
    _registerRouteScoped<ChatController>(() => ChatController());
    _registerRouteScoped<EventController>(() => EventController());
    _registerRouteScoped<OffreController>(() => OffreController());
  }

  void _registerRouteScoped<T>(T Function() builder) {
    // The normal path: bootstrap already put a permanent instance here.
    if (Get.isRegistered<T>() || Get.isPrepared<T>()) {
      return;
    }

    Get.lazyPut<T>(builder, fenix: true);
  }
}
