import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// App Check runs in "soft" mode in production, deliberately and permanently.
///
/// This is not a TODO waiting to be closed. Play Integrity attestation fails
/// on a large share of the real device fleet this app serves — Play-uncertified
/// handsets, missing or outdated Play services, slow first attestation — and
/// production logs showed `403 App attestation failed` on ordinary user
/// phones. Under "enforce" that one signal took down every mobile callable at
/// once: uploads, likes, follows, FCM token registration, even the client
/// logging that would have made the outage visible.
///
/// These tests exist because the change that breaks it is a one-word edit in
/// an env file, and the damage only shows up on real handsets — never in CI,
/// never on a developer's Play-certified test device.
void main() {
  group('App Check stays in soft mode', () {
    test('the versioned production env examples do not enforce', () {
      const productionEnvExamples = <String>[
        'functions/.env.production.example',
        'functions/.env.production-next.example',
      ];

      for (final path in productionEnvExamples) {
        final env = File(path).readAsStringSync();

        expect(
          env,
          contains('APP_CHECK_MODE=soft'),
          reason: '$path must keep App Check in soft mode',
        );
        expect(
          env,
          isNot(contains('APP_CHECK_MODE=enforce')),
          reason: '$path would reject uploads from most real devices',
        );
      }
    });

    test('soft mode still reads and reports the token', () {
      final runtime =
          File('functions/src/function_runtime.ts').readAsStringSync();

      // Soft is not "off": dropping enforcement must not cost us the signal.
      expect(runtime, contains('APP_CHECK_MODE'));
      expect(runtime, contains('READ_APP_CHECK_TOKEN'));
      expect(runtime, contains('logAppCheckState'));
      expect(runtime, contains('const ENFORCE_APP_CHECK = APP_CHECK_MODE === "enforce"'));
    });

    test('the decision and its compensating controls are written down', () {
      final runtime =
          File('functions/src/function_runtime.ts').readAsStringSync();

      // A future reader must find the reasoning next to the switch, not have
      // to reconstruct it from an outage.
      expect(runtime, contains('Play Integrity'));
      expect(runtime, contains('settled decision'));
      expect(runtime, contains('no self-signup'));
    });
  });

  group('controls that replace enforcement', () {
    test('outbound push paths are rate limited per user', () {
      final actions = File('functions/src/actions.ts').readAsStringSync();

      // One authenticated fanout notifies every player in the database.
      // Owning the offer bounds *who* may announce it, not how often.
      expect(actions, contains('MAX_FANOUTS_PER_HOUR'));
      expect(actions, contains('MAX_DIRECT_PUSHES_PER_MINUTE'));

      final fanoutLimited = RegExp(
        r'enforceCallRateLimit\(\s*"push_call_limits",\s*`fanout_\$\{uid\}`',
      ).allMatches(actions).length;
      expect(
        fanoutLimited,
        2,
        reason: 'both sendOfferFanout and sendEventFanout must be limited',
      );

      expect(
        actions,
        contains(r'`directPush_${uid}`'),
        reason: 'sendUserPush must be limited too',
      );
    });

    test('rate-limit counters are unreachable from any client', () {
      final rules = File('firestore.rules').readAsStringSync();

      // A client that can reset its own window has no rate limit at all.
      expect(rules, contains('match /push_call_limits/{docId}'));
      expect(rules, contains('match /log_call_limits/{docId}'));
    });

    test('the upload path keeps its own quotas independent of App Check', () {
      final uploadSession =
          File('functions/src/upload_session.ts').readAsStringSync();

      expect(uploadSession, contains('MAX_VIDEO_UPLOADS_PER_DAY'));
      expect(uploadSession, contains('MAX_CONCURRENT_VIDEO_UPLOADS'));
      expect(uploadSession, contains('MAX_PENDING_VIDEO_REVIEWS'));
      expect(uploadSession, contains('MAX_PUBLIC_PLAYER_VIDEOS'));
      expect(uploadSession, contains('MAX_VIDEO_UPLOAD_FILE_SIZE_BYTES'));
      expect(uploadSession, contains('MAX_VIDEO_UPLOAD_DURATION_SECONDS'));
    });
  });
}
