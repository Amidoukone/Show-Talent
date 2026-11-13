import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iOS release build gets its configuration only through `--dart-define`,
/// and every define the workflow forgets silently falls back to the Dart
/// default rather than failing.
///
/// That is how iOS shipped with dead account-activation links from build 53 to
/// 58. `EMAIL_LINK_CUSTOM_HOST` was absent from `codemagic.yaml`, so
/// `AppEnvironmentConfig.emailLinkHost` fell back to
/// `<project>.firebaseapp.com` and `adfoot.org` dropped out of
/// `emailLinkAllowedHosts`. Meanwhile `apple-app-site-association` routes
/// `/account/reset*` and `/account/verify*` on adfoot.org straight into the
/// app, so the link opened Adfoot and `EmailLinkHandler._handle()` returned
/// false without a word. No Safari fallback: iOS had already handed over.
///
/// Android never had the problem, because its scripts pass the whole of
/// `config/mobile/production.json`.
void main() {
  final codemagic = File('codemagic.yaml').readAsStringSync();
  final iosProduction = codemagic.substring(
    codemagic.indexOf('  ios-production:'),
    codemagic.indexOf('  ios-simulator-preview:'),
  );

  Set<String> definesOf(String workflow) =>
      RegExp(r'dart-define=([A-Z_]+)')
          .allMatches(workflow)
          .map((match) => match.group(1)!)
          .toSet();

  test('the iOS production build passes what the app actually reads', () {
    const required = <String>{
      'APP_ENV',
      'VIDEO_SHARE_BASE_URL',
      'FIREBASE_PROJECT_ID',
      'FIREBASE_MESSAGING_SENDER_ID',
      'FIREBASE_STORAGE_BUCKET',
      'FIREBASE_IOS_API_KEY',
      'FIREBASE_IOS_APP_ID',
      'FIREBASE_IOS_BUNDLE_ID',
      // The two that were missing. Keep them listed by name so a future
      // reader sees why they matter rather than a bare count.
      'EMAIL_LINK_CUSTOM_HOST',
      'APP_CHECK_ENABLED',
    };

    expect(
      definesOf(iosProduction),
      containsAll(required),
      reason:
          'A define missing here does not fail the build; it silently takes '
          'the Dart default and ships wrong behaviour.',
    );
  });

  test('iOS production carries the same values Android production does', () {
    // production.example.json, not production.json: the real file is
    // gitignored because it carries API keys, so it does not exist on CI.
    // The example is the committed contract for the non-secret values, and
    // these three are exactly that. Reading the real file is what made this
    // guardrail pass locally and fail on CI the first time round.
    final android = jsonDecode(
      File('config/mobile/production.example.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    // Only the keys iOS also declares inline: the Firebase ones legitimately
    // differ per platform and come from a Codemagic group.
    for (final key in const <String>[
      'EMAIL_LINK_CUSTOM_HOST',
      'APP_CHECK_ENABLED',
      'VIDEO_SHARE_BASE_URL',
    ]) {
      expect(
        iosProduction,
        contains('$key: "${android[key]}"'),
        reason:
            '$key must match config/mobile/production.json, or the two '
            'platforms ship different behaviour from the same commit',
      );
    }
  });

  test('adfoot.org stays routed to the app, which is why the host matters', () {
    final aasa = File('site_pub/.well-known/apple-app-site-association')
        .readAsStringSync();

    // If these paths ever stop reaching the app, the host allowlist stops
    // being load-bearing and this whole guardrail can be revisited.
    expect(aasa, contains('/account/reset*'));
    expect(aasa, contains('/account/verify*'));
  });
}
