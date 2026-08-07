import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'profile screen keeps the newest visible videos in the profile grid',
    () {
      final profile = File(
        'lib/screens/profile_screen.dart',
      ).readAsStringSync();

      expect(
        profile,
        contains(
          'return full.take(_visibleWindowSize).toList(growable: false);',
        ),
      );
    },
  );
}
