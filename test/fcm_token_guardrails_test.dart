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
}
