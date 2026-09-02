import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `scripts/check-aab-contents.ps1` reads the compiled bundle and asks whether
/// it contains this checkout. Its witnesses live in a JSON file, and a witness
/// only says something while the source and the file agree: a witness that no
/// longer exists in `lib/` fails every build for nothing, and a forbidden
/// string that came back into `lib/` would be reported as a cached build.
///
/// This is the pair the incident of 1.0.7+31 asked for. That build shipped the
/// previous release's Dart snapshot with a correct manifest; nothing read the
/// artifact. Now something does — and this test keeps what it reads honest.
void main() {
  final expectations =
      jsonDecode(
            File('scripts/aab-content-expectations.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  List<Map<String, dynamic>> entries(String key) =>
      ((expectations[key] as List<dynamic>?) ?? <dynamic>[])
          .cast<Map<String, dynamic>>();

  String allDartSources() {
    final buffer = StringBuffer();
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        buffer.writeln(entity.readAsStringSync());
      }
    }
    return buffer.toString();
  }

  test('every witness string still exists in lib/', () {
    final sources = allDartSources();
    final witnesses = entries('mustContain');

    expect(witnesses, isNotEmpty);
    for (final witness in witnesses) {
      expect(
        sources,
        contains(witness['text'] as String),
        reason:
            'Le temoin "${witness['text']}" n\'est plus dans lib/. '
            'Il ferait echouer chaque build. Remplacez-le dans '
            'scripts/aab-content-expectations.json par une chaine que cette '
            'release ajoute reellement.',
      );
    }
  });

  test('every forbidden string is really absent from lib/', () {
    final sources = allDartSources();
    final forbidden = entries('mustNotContain');

    for (final witness in forbidden) {
      expect(
        sources,
        isNot(contains(witness['text'] as String)),
        reason:
            '"${witness['text']}" est revenu dans lib/. Le controle du bundle '
            'le lirait comme la signature d\'un build cache.',
      );
    }
  });

  test('witnesses were reviewed for the versionCode being built', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*[0-9.]+\+([0-9]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(version, isNotNull);
    expect(
      expectations['forVersionCode'],
      int.parse(version!.group(1)!),
      reason:
          'Les temoins ont ete choisis pour une autre release. Relisez-les : '
          'un temoin ne vaut que s\'il discrimine ce build du precedent, puis '
          'mettez forVersionCode a jour.',
    );
  });

  test('the build refuses a bundle that does not contain this checkout', () {
    final build = File('scripts/build-android-release.ps1').readAsStringSync();

    expect(build, contains('check-aab-contents.ps1'));
    expect(build, contains(r'[switch]$SkipContentCheck'));
    expect(build, contains(r'if ($LASTEXITCODE -ne 0)'));
  });

  test('the bundle check searches all three Dart string encodings', () {
    final script = File('scripts/check-aab-contents.ps1').readAsStringSync();

    // Dart stores a literal as a OneByteString when it fits in one byte per
    // character, as UTF-16 otherwise -- never as UTF-8. Searching UTF-8 alone
    // reports "Annee de naissance" as absent from a bundle that carries it,
    // which is how a working build gets blamed.
    expect(script, contains('GetEncoding(28591)'));
    expect(script, contains('Encoding]::UTF8.GetBytes'));
    expect(script, contains('Encoding]::Unicode.GetBytes'));
    // The one check that needs no list: the same Dart cannot compile twice
    // into two different snapshots, so an identical one means a cache.
    expect(script, contains('identique au bundle precedent'));
  });
}
