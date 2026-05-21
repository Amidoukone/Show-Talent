import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter source text does not contain common mojibake sequences', () {
    const forbidden = <String>[
      '\u{00C3}',
      '\u{00E2}\u{20AC}\u{2122}',
      '\u{00E2}\u{20AC}\u{0153}',
      '\u{00E2}\u{20AC}',
      '\u{00E2}\u{20AC}\u{00A6}',
      '\u{00E2}\u{201A}\u{00AC}',
      '\u{00F0}\u{0178}',
      '\u{FFFD}',
    ];

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }

      final content = entity.readAsStringSync();
      for (final sequence in forbidden) {
        if (content.contains(sequence)) {
          offenders.add('${entity.path}: $sequence');
        }
      }
    }

    expect(offenders, isEmpty);
  });
}
