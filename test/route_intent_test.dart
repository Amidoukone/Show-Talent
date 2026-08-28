import 'package:adfoot/services/route_intent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// `Get.arguments` stays set for the whole life of a route, while every screen
/// inside `MainScreen` is disposed and rebuilt each time the user leaves its
/// tab and comes back. Reading the arguments in `initState` therefore acted on
/// the same request again on every visit: a shared video link dragged the feed
/// back to that video, and "Offre publiée" was announced long after the fact.
void main() {
  setUp(() {
    RouteIntent.resetForTests();
    Get.routing.args = null;
  });

  tearDown(() {
    RouteIntent.resetForTests();
    Get.routing.args = null;
  });

  test('the first read gets the arguments and the second gets nothing', () {
    Get.routing.args = <String, dynamic>{'videoId': 'abc'};

    expect(RouteIntent.readOnce('home_playback'), <String, dynamic>{
      'videoId': 'abc',
    });
    expect(
      RouteIntent.readOnce('home_playback'),
      isNull,
      reason: 'returning to the tab must not replay the request',
    );
    expect(RouteIntent.readOnce('home_playback'), isNull);
  });

  test('consumers do not eat each other\'s intent', () {
    Get.routing.args = <String, dynamic>{
      'videoId': 'abc',
      'offerSystemNoticeMessage': 'Offre publiée',
    };

    expect(RouteIntent.readOnce('home_playback'), isNotNull);
    expect(
      RouteIntent.readOnce('offer_notice'),
      isNotNull,
      reason: 'two screens read different keys of the same arguments',
    );
    expect(RouteIntent.readOnce('home_playback'), isNull);
    expect(RouteIntent.readOnce('offer_notice'), isNull);
  });

  test('the next navigation re-opens every consumer', () {
    Get.routing.args = <String, dynamic>{'videoId': 'first'};
    expect(RouteIntent.readOnce('home_playback'), isNotNull);
    expect(RouteIntent.readOnce('home_playback'), isNull);

    // A genuinely new intent — a second shared link, a fresh publication.
    Get.routing.args = <String, dynamic>{'videoId': 'second'};
    final second = RouteIntent.readOnce('home_playback');
    expect(second, isNotNull);
    expect(second!['videoId'], 'second');
  });

  test('a route with no map carries no intent', () {
    expect(RouteIntent.readOnce('home_playback'), isNull);

    // `offres_form` passes an Offre instance as arguments when editing.
    Get.routing.args = 'not a map';
    expect(RouteIntent.readOnce('offer_notice'), isNull);
  });

  test('a push and a pop do not re-open a consumed intent', () {
    // `Get.arguments` follows the navigation stack, not the route these
    // screens live on. Opening a form from the shell sets it to null, or to
    // an Offre when editing; popping restores /main's map. None of that is a
    // new intent, and treating it as one would replay the old one.
    final mainArgs = <String, dynamic>{'videoId': 'abc'};

    Get.routing.args = mainArgs;
    expect(RouteIntent.readOnce('home_playback'), isNotNull);

    // A form is pushed: no arguments.
    Get.routing.args = null;
    expect(RouteIntent.readOnce('home_playback'), isNull);

    // Editing an existing offer pushes the Offre itself as the arguments.
    Get.routing.args = Object();
    expect(RouteIntent.readOnce('offer_notice'), isNull);

    // Popping back restores the shell's arguments, same instance.
    Get.routing.args = mainArgs;
    expect(
      RouteIntent.readOnce('home_playback'),
      isNull,
      reason: 'the feed must not jump back to the shared video again',
    );
    expect(RouteIntent.readOnce('offer_notice'), isNotNull);
  });

  test('identical arguments seen twice are still consumed once', () {
    final args = <String, dynamic>{'refresh': true};

    Get.routing.args = args;
    expect(RouteIntent.readOnce('home_playback'), isNotNull);

    // The shell re-reads while the same route is still installed.
    Get.routing.args = args;
    expect(RouteIntent.readOnce('home_playback'), isNull);
  });
}
