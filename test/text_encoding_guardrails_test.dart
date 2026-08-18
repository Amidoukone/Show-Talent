import 'dart:convert';
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

    const sourceRoots = <String>['lib', 'functions/src', 'site_pub', 'scripts'];
    const sourceExtensions = <String>{
      '.dart',
      '.ts',
      '.js',
      '.html',
      '.mjs',
      '.ps1',
    };
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

  // A UTF-8 BOM here is not cosmetic. Google's Digital Asset Links API and
  // Apple's AASA fetcher both parse these files as strict JSON and reject a
  // leading EF BB BF outright ("Could not parse statement list (not valid
  // JSON)"). A rejected statement list silently turns off App Links
  // verification for every android:autoVerify intent-filter in
  // AndroidManifest.xml: email verification links (/__/auth/action) and
  // shared video links (/v/**) stop opening in the app and fall back to the
  // browser, with no error surfaced anywhere. Production shipped exactly that
  // regression, introduced by `Set-Content -Encoding UTF8` in
  // scripts/update-assetlinks-fingerprints.ps1 (Windows PowerShell 5.1 writes
  // a BOM for that encoding name).
  test('deep-link association files are BOM-free and parse as strict JSON', () {
    const associationFiles = <String>[
      'site_pub/.well-known/assetlinks.json',
      'site_pub/.well-known/apple-app-site-association',
    ];

    for (final path in associationFiles) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing');

      final bytes = file.readAsBytesSync();
      final hasBom = bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF;
      expect(
        hasBom,
        isFalse,
        reason: '$path starts with a UTF-8 BOM; strict JSON parsers reject it',
      );

      expect(
        () => jsonDecode(utf8.decode(bytes)),
        returnsNormally,
        reason: '$path is not valid JSON',
      );
    }
  });

  // The PowerShell generators must not reintroduce the BOM the test above
  // guards against.
  test('deep-link association generators never write with Set-Content UTF8',
      () {
    for (final path in const <String>[
      'scripts/update-assetlinks-fingerprints.ps1',
      'scripts/update-apple-app-site-association.ps1',
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;

      expect(
        file.readAsStringSync(),
        isNot(contains('Set-Content -LiteralPath')),
        reason: '$path must use UTF8Encoding(\$false) so no BOM is emitted',
      );
    }
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
