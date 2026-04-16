import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android app links support Firebase auth domains for active environments',
      () {
    final content =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(content, contains('android:host="adfoot-staging.firebaseapp.com"'));
    expect(content, contains('android:host="adfoot-production.firebaseapp.com"'));
    expect(content, contains('android:pathPrefix="/__/auth/action"'));
  });
}
