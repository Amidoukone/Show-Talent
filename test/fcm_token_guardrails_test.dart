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

  // saveFcmToken swallowed both its failures and returned as though it had
  // worked. The backend then kept the previous token, FCM rejected it on the
  // next send, pruneUnregisteredToken deleted it, and the device received no
  // notifications at all until FCM happened to rotate again -- which can be
  // months. Nothing was logged, and the try/catch wrapped around the call in
  // listenTokenRefresh was dead code, because the method could not throw.
  test('a failed token save is retried, and reported if it never lands', () {
    final repository =
        File('lib/services/users/user_repository.dart').readAsStringSync();

    expect(repository, contains('Future<bool> _writeFcmToken('));
    expect(repository, contains('Future<void> _retryFcmTokenSave('));
    expect(repository, contains('static const int _fcmTokenRetryAttempts'));

    // Reported at `error`: `warning` is sampled at 15%, and this is a
    // per-device capability loss rather than noise.
    expect(repository, contains("source: 'notifications/token_save'"));
    expect(repository, contains('AppLogger.error('));
  });

  // Three callers await saveFcmToken and one of them sits in
  // AuthController._syncState, on the path a sign-in waits for. Retrying
  // inline would put up to 24 seconds of backoff in front of the session.
  test('the retry never delays a caller', () {
    final repository =
        File('lib/services/users/user_repository.dart').readAsStringSync();

    final save = repository.indexOf('Future<void> saveFcmToken(');
    expect(save, isNonNegative);
    final body = repository.substring(save, save + 700);

    expect(body, contains('unawaited(_retryFcmTokenSave('));
    expect(
      body,
      isNot(contains('await _retryFcmTokenSave(')),
      reason: 'a sign-in must never wait on the backoff',
    );
    // The first attempt keeps its original shape: no delay before it.
    expect(body, contains('if (await _writeFcmToken(uid, sanitized))'));
  });

  // FCM can hand over a new token while a retry for the previous one is
  // still sleeping. A late success would then write the *old* token over the
  // new one -- the dead-token state this is meant to prevent.
  test('a superseded token cannot overwrite a newer one', () {
    final repository =
        File('lib/services/users/user_repository.dart').readAsStringSync();

    expect(repository, contains('static int _fcmTokenSaveSerial'));
    expect(repository, contains('final serial = ++_fcmTokenSaveSerial;'));
    expect(repository, contains('if (serial != _fcmTokenSaveSerial)'));
    // And it must not attach this device's token to another account.
    expect(
      repository,
      contains('if (FirebaseAuth.instance.currentUser?.uid != uid)'),
    );
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
