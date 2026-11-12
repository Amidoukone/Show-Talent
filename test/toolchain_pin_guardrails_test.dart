import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Flutter version this repository is built and verified on lives in four
/// places, and nothing used to compare them.
///
/// They drifted exactly the way an unchecked duplicate does: the workstation
/// moved to Flutter 3.50 while `.github/workflows/ci.yml` and all three
/// `codemagic.yaml` workflows stayed on 3.44.2 -- and 3.44.2 ships a Dart
/// below the floor `pubspec.lock` already required (`file_selector_macos`
/// 0.9.5+2 needs Dart 3.13 / Flutter 3.47). Nothing failed loudly: `pub get`
/// quietly re-resolves a different dependency set when the locked one does not
/// fit the SDK, so CI would have gone on passing against packages nobody ran
/// locally, and Codemagic would have archived the shipping IPA from them.
///
/// The App Store build must come off the toolchain the test suite ran on.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final declared = RegExp(
    r'''^\s*flutter:\s*"?>=(\d+\.\d+\.\d+)"?\s*$''',
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);

  test('pubspec declares the Flutter floor it is built on', () {
    expect(
      declared,
      isNotNull,
      reason: 'pubspec.yaml must keep an explicit `flutter: ">=x.y.z"` floor',
    );
  });

  test('CI builds on the Flutter version pubspec declares', () {
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    final pinned = RegExp(r'flutter-version:\s*"(\d+\.\d+\.\d+)"')
        .firstMatch(ci)
        ?.group(1);

    expect(
      pinned,
      declared,
      reason:
          'ci.yml analyzes and tests the code; running it on a different '
          'Flutter than pubspec declares makes a green CI meaningless',
    );
  });

  test('every Codemagic workflow builds on that same version', () {
    final codemagic = File('codemagic.yaml').readAsStringSync();
    final pins = RegExp(
      r'^\s+flutter:\s*(\d+\.\d+\.\d+)',
      multiLine: true,
    ).allMatches(codemagic).map((match) => match.group(1)).toList();

    // Staging, production and the simulator preview. A workflow added without
    // a pin, or with its own, is the drift this test exists to catch.
    expect(
      pins,
      hasLength(3),
      reason: 'each Codemagic workflow must pin an explicit Flutter version',
    );
    for (final pin in pins) {
      expect(
        pin,
        declared,
        reason: 'Codemagic archives the IPA Apple receives',
      );
    }
  });
}
