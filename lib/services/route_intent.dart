import 'package:get/get.dart';

/// One-shot reads of the arguments carried by the current route.
///
/// `Get.arguments` stays set for the whole life of a route — it is only
/// replaced by the next navigation. That is fine for a screen that is built
/// once, and wrong for every screen inside `MainScreen`, which swaps its body
/// between destinations rather than keeping them in an `IndexedStack`:
/// leaving a tab disposes its `State`, and coming back builds a new one that
/// reads the same arguments again.
///
/// The consequences were real and both looked like the app misbehaving on its
/// own:
///
///  * a shared video link put `videoId` in the arguments, so `HomeScreen`
///    jumped the feed back to that video and refetched — not once, but every
///    single time the user returned to Accueil;
///  * publishing an offer put a notice in the arguments, so "Offre publiée"
///    reappeared each time the Offres tab was opened.
///
/// A `bool _hasHandled` field on the `State` cannot fix either, because it is
/// the `State` itself that is recreated. The flag has to outlive it, which is
/// what this holds — keyed per consumer, so two screens reading different
/// parts of the same arguments do not consume each other's.
///
/// The set is cleared whenever the arguments object changes identity, i.e. on
/// the next navigation, so a genuinely new intent is always delivered.
class RouteIntent {
  const RouteIntent._();

  static Object? _argumentsIdentity;
  static final Set<String> _consumed = <String>{};

  /// The current route arguments, the first time [key] asks for them.
  ///
  /// Returns null on every later call for the same [key] and the same
  /// arguments, and null when the route carries no map.
  static Map<dynamic, dynamic>? readOnce(String key) {
    final arguments = Get.arguments;

    // Checked before the ledger is touched, and that order matters.
    //
    // `Get.arguments` follows the navigation stack, not the route these
    // screens live on: pushing sets it to the pushed route's arguments (null
    // for a plain `Get.to`, an `Offre` when editing one) and popping restores
    // the previous route's. Treating those as a new intent would clear the
    // ledger and let `/main`'s arguments be acted on a second time when the
    // user came back — the exact replay this class exists to stop.
    //
    // Nothing that is not a map can carry an intent, so it is simply not an
    // answer to this question.
    if (arguments is! Map) {
      return null;
    }

    if (!identical(arguments, _argumentsIdentity)) {
      _argumentsIdentity = arguments;
      _consumed.clear();
    }

    if (!_consumed.add(key)) {
      return null;
    }

    return arguments;
  }

  /// Forgets what has been consumed.
  ///
  /// Only for tests: the state is static, so one test's consumption would
  /// otherwise silence the next one.
  static void resetForTests() {
    _argumentsIdentity = null;
    _consumed.clear();
  }
}
