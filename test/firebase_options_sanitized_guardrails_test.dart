import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('committed Firebase options stay sanitized', () {
    final source = File('lib/firebase_options.dart').readAsStringSync();

    expect(source, isNot(contains(RegExp(r'AIza[0-9A-Za-z_-]{20,}'))));
    expect(source, isNot(contains('adfoot-production')));
    expect(source, contains('firebase-api-key-placeholder'));
    expect(source, contains('firebase-project-placeholder'));
  });
}
