import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrails for the one class of failure this app could not see.
///
/// On 2026-08-23 the app died during video playback on the first launch of
/// 1.0.7+24, and Crashlytics reported **100% crash-free users and 100%
/// crash-free sessions** for that release, with no issues at all. The report
/// would have been written at crash time and uploaded on the next launch, and
/// the tester did relaunch — so it was not a Dart error and not an uncaught
/// Java/Kotlin exception either. It was a native signal, and nothing in the
/// build was listening for one.
String _read(String path) => File(path).readAsStringSync();

void main() {
  group('a native crash has somewhere to be recorded', () {
    test('the app module ships firebase-crashlytics-ndk', () {
      final app = _read('android/app/build.gradle');

      expect(
        app,
        contains('com.google.firebase:firebase-crashlytics-ndk'),
        reason: 'the Flutter plugin reports Dart errors and the Android SDK '
            'reports Java ones; neither sees a SIGSEGV',
      );
      expect(
        app,
        contains('com.google.firebase.crashlytics'),
        reason: 'the Gradle plugin has to be applied for either to work',
      );
    });

    // Crashlytics NDK has to match the Crashlytics version exactly, or the
    // native reports do not attach to the Java ones. The FlutterFire plugins
    // resolve the BoM through `rootProject.ext.FirebaseSDKVersion` before
    // falling back to their own default, so pinning it at the root is what
    // stops :app and the plugins drifting apart.
    test('one Firebase BoM governs every module', () {
      final root = _read('android/build.gradle');
      final app = _read('android/app/build.gradle');

      expect(root, contains('ext.FirebaseSDKVersion = '));
      expect(
        app,
        contains(r'firebase-bom:${rootProject.ext.FirebaseSDKVersion}'),
        reason: ':app must not pin a version of its own',
      );
    });

    // The pinned value has to stay in step with the default that firebase_core
    // ships, otherwise upgrading the package silently moves the plugins while
    // :app stays behind.
    test('the pinned BoM matches what firebase_core expects', () {
      final root = _read('android/build.gradle');
      final pinned = RegExp(r'ext\.FirebaseSDKVersion\s*=\s*"([^"]+)"')
          .firstMatch(root)
          ?.group(1);
      expect(pinned, isNotNull, reason: 'no pinned FirebaseSDKVersion found');

      final config = jsonDecode(
        _read('.dart_tool/package_config.json'),
      ) as Map<String, dynamic>;
      final packages = (config['packages'] as List).cast<Map<String, dynamic>>();
      final core = packages.firstWhere(
        (package) => package['name'] == 'firebase_core',
        orElse: () => <String, dynamic>{},
      );
      expect(core, isNotEmpty, reason: 'firebase_core is not resolved');

      final properties = File.fromUri(
        Uri.parse('${core['rootUri']}/android/gradle.properties'),
      );
      expect(
        properties.existsSync(),
        isTrue,
        reason: 'cannot read ${properties.path}',
      );

      final expected = RegExp(r'FirebaseSDKVersion\s*=\s*(\S+)')
          .firstMatch(properties.readAsStringSync())
          ?.group(1);
      expect(expected, isNotNull);
      expect(
        pinned,
        expected,
        reason: 'android/build.gradle pins $pinned but firebase_core '
            '$expected — upgrading the package moved the plugins and left '
            ':app behind',
      );
    });

    // Off in debug so a dev machine does not fill the dashboard; on for every
    // real build, which is the only reason the 1.0.7+24 report is trustworthy
    // when it says there was nothing to report.
    test('collection is on for every build that is not debug', () {
      expect(
        _read('lib/config/app_bootstrap.dart'),
        contains('setCrashlyticsCollectionEnabled(\n          !kDebugMode,\n        )'),
      );
    });
  });
}
