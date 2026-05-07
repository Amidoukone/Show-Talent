import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user access watcher revalidates session before forced sign-out', () {
    final source =
        File('lib/controller/user_controller.dart').readAsStringSync();

    expect(source, contains('_currentUserAccessSub ='));
    expect(source, contains('unawaited(_enforceCurrentSessionAccess());'));
    expect(
      source,
      isNot(
        contains('unawaited(_handleCurrentUserAccessRevoked(decision));'),
      ),
    );
  });
}
