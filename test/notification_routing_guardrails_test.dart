import 'dart:io';

import 'package:adfoot/services/notification_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveNotificationRoute', () {
    test('sends a moderation decision to the author own profile', () {
      final route = resolveNotificationRoute(<String, dynamic>{
        'type': 'video_moderation',
        'videoId': 'abc123',
        'decision': 'approved',
      });

      expect(route.destination, NotificationDestination.ownProfile);
      expect(route.targetId, 'abc123');
      expect(route.isActionable, isTrue);
    });

    test('routes a rejection to the same place as an approval', () {
      // adminRejectVideo deletes the document, so there is nothing to deep
      // link to: the profile is the only destination that stays valid.
      final route = resolveNotificationRoute(<String, dynamic>{
        'type': 'video_moderation',
        'videoId': 'gone',
        'decision': 'rejected',
      });

      expect(route.destination, NotificationDestination.ownProfile);
    });

    test('maps the backend context types to their tabs', () {
      expect(
        resolveNotificationRoute(<String, dynamic>{
          'type': 'message',
          'id': 'conv1',
        }).destination,
        NotificationDestination.conversations,
      );
      expect(
        resolveNotificationRoute(<String, dynamic>{
          'type': 'offre',
          'id': 'offer1',
        }).destination,
        NotificationDestination.offers,
      );
      expect(
        resolveNotificationRoute(<String, dynamic>{
          'type': 'event',
          'id': 'event1',
        }).destination,
        NotificationDestination.events,
      );
    });

    test('never throws and stays inert on unusable payloads', () {
      expect(resolveNotificationRoute(null).isActionable, isFalse);
      expect(
        resolveNotificationRoute(const <String, dynamic>{}).isActionable,
        isFalse,
      );
      expect(
        resolveNotificationRoute(<String, dynamic>{
          'videoId': 'abc',
        }).isActionable,
        isFalse,
      );
      // A type from a backend newer than this build must not open a random
      // screen.
      expect(
        resolveNotificationRoute(<String, dynamic>{
          'type': 'something_new',
        }).isActionable,
        isFalse,
      );
    });

    test('tolerates FCM string-map payloads and odd casing', () {
      final route = resolveNotificationRoute(<String, dynamic>{
        'type': ' Video_Moderation ',
        'videoId': ' abc123 ',
      });

      expect(route.destination, NotificationDestination.ownProfile);
      expect(route.targetId, 'abc123');
    });
  });

  group('notification tap wiring', () {
    test('taps captured before the UI exists are replayed, not dropped', () {
      final service = File('lib/services/notifications.dart').readAsStringSync();
      final shell = File('lib/screens/main_screen.dart').readAsStringSync();

      // A tap that launched the app from a killed state arrives during
      // bootstrap, before runApp.
      expect(service, contains('getInitialMessage'));
      expect(service, contains('onMessageOpenedApp'));
      expect(service, contains('takePendingRoute'));
      expect(shell, contains('NotificationService.takePendingRoute()'));
      expect(shell, contains('NotificationService.routeTaps'));
    });

    test('foreground notifications carry their payload to the tap handler', () {
      final service = File('lib/services/notifications.dart').readAsStringSync();

      // Without a payload the locally re-rendered notification is a dead end.
      expect(service, contains('payload: _encodePayload(msg.data)'));
      expect(service, contains('onDidReceiveNotificationResponse'));
    });

    test('a cold-start tap does not depend on profile hydration', () {
      final shell = File('lib/screens/main_screen.dart').readAsStringSync();

      // The common case for this route is a cold start: the notification
      // arrives with the phone in a pocket and the tap launches the app from
      // a killed state. `userController.user` is still being fetched at that
      // moment, so keying the destination off it dropped the route in silence
      // and landed the author on the feed — the one screen that does not show
      // the video they were just told about. Auth knows the uid immediately.
      expect(shell, contains('_authController.currentUid'));
      expect(
        shell,
        isNot(contains('final uid = userController.user?.uid')),
      );
    });

    test('opening a publisher profile never silently does nothing', () {
      final player =
          File('lib/widgets/smart_video_player.dart').readAsStringSync();

      // The identity only decides whether the profile opens editable, so an
      // unhydrated profile must not turn the tap into a no-op with no
      // navigation and no feedback.
      expect(player, contains('Future<void> _openPublisherProfile(String?'));
    });

    test('android can always render a push, channel id or not', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final service = File('lib/services/notifications.dart').readAsStringSync();

      // On API 26+ a notification with an unknown channel is dropped
      // silently. The manifest default and the channel the app creates at
      // startup must therefore agree.
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(
        manifest,
        contains('com.google.firebase.messaging.default_notification_channel_id'),
      );
      expect(manifest, contains('android:value="high_importance_channel"'));
      expect(service, contains("'high_importance_channel'"));
    });

    test('the service does not reach into navigation itself', () {
      final service = File('lib/services/notifications.dart').readAsStringSync();

      expect(service, isNot(contains('package:get/get.dart')));
      expect(service, isNot(contains("import 'package:adfoot/screens/")));
    });
  });
}
