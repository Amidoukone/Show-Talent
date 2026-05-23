import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source text does not contain common mojibake sequences', () {
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

    const sourceRoots = <String>['lib', 'functions/src', 'site_pub'];
    const sourceExtensions = <String>{'.dart', '.ts', '.js', '.html'};
    final offenders = <String>[];
    for (final root in sourceRoots) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;

      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !sourceExtensions.any(entity.path.endsWith)) {
          continue;
        }

        final content = entity.readAsStringSync();
        for (final sequence in forbidden) {
          if (content.contains(sequence)) {
            offenders.add('${entity.path}: $sequence');
          }
        }
      }
    }

    expect(offenders, isEmpty);
  });

  test('auth screens keep common French accents in visible copy', () {
    const forbiddenPhrases = <String>[
      'Connexion echouee',
      'Mot de passe oublie',
      'au moins 6 caracteres',
      'Reinitialiser le mot de passe',
    ];

    final offenders = <String>[];
    for (final path in const <String>[
      'lib/screens/login_screen.dart',
      'lib/screens/reset_password_screen.dart',
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;

      final content = file.readAsStringSync();
      for (final phrase in forbiddenPhrases) {
        if (content.contains(phrase)) {
          offenders.add('$path: $phrase');
        }
      }
    }

    expect(offenders, isEmpty);
  });
}
