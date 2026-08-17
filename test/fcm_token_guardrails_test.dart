import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FCM token persistence goes through the authenticated callable first',
      () {
    final repository =
        File('lib/services/users/user_repository.dart').readAsStringSync();
    final notifications =
        File('lib/services/notifications.dart').readAsStringSync();
    final actions = File('functions/src/actions.ts').readAsStringSync();
    final index = File('functions/src/index.ts').readAsStringSync();

    expect(repository, contains("httpsCallable('saveUserFcmToken')"));
    expect(notifications, contains('UserRepository().saveFcmToken'));
    expect(notifications, isNot(contains("collection('users').doc")));
    expect(actions, contains('export const saveUserFcmToken = onCall'));
    expect(index, contains('saveUserFcmToken'));
  });

  test('token rotation is observed, not only captured at sign-in', () {
    final notifications =
        File('lib/services/notifications.dart').readAsStringSync();
    final bootstrap = File('lib/config/app_bootstrap.dart').readAsStringSync();

    // FCM rotates tokens on reinstall/restore/inactivity. Persisting only at
    // sign-in leaves the backend holding a dead token, and every later
    // notification is dropped by FCM with no visible error.
    expect(notifications, contains('onTokenRefresh'));
    expect(notifications, contains('listenTokenRefresh'));
    expect(bootstrap, contains('NotificationService.listenTokenRefresh'));
  });

  test('dead tokens are pruned server-side on every send path', () {
    final pushDelivery =
        File('functions/src/push_delivery.ts').readAsStringSync();
    final actions = File('functions/src/actions.ts').readAsStringSync();
    final adminContent =
        File('functions/src/admin_content_actions.ts').readAsStringSync();

    expect(
      pushDelivery,
      contains('messaging/registration-token-not-registered'),
    );
    // invalid-argument is also raised for a malformed payload; pruning on it
    // would delete a valid token because of a bug elsewhere.
    expect(pushDelivery, isNot(contains('"messaging/invalid-argument"')));
    // Compare-and-clear: never wipe a replacement token that arrived while
    // the failing send was in flight.
    expect(pushDelivery, contains('runTransaction'));

    expect(actions, contains('handlePushSendError'));
    expect(actions, contains('pruneUnregisteredToken'));
    expect(adminContent, contains('handlePushSendError'));
  });

  test('the fanout keeps the uid that owns each token', () {
    final actions = File('functions/src/actions.ts').readAsStringSync();

    // Collecting bare tokens made sendEachForMulticast failures
    // unattributable, so a dead token could never be cleaned up and stayed in
    // every future fanout.
    expect(actions, contains('listPlayerTargets'));
    expect(actions, isNot(contains('listPlayerTokens')));
    expect(actions, contains('type PlayerPushTarget'));
  });
}
