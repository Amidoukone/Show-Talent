import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrails for the go-live hardening pass on 1.0.7+18.
///
/// Each test pins one failure that was live in the shipped code and that no
/// existing test could see, because none of them is a crash: they are a
/// spinner that never ends, a retry loop nobody counts, a metric quietly
/// destroyed by its own reporting. Source-level assertions, in the style the
/// rest of `test/` already uses, so a refactor that removes the fix has to
/// say so out loud.
/// Reads a source file with its line endings normalised.
///
/// The multi-line assertions below match across a newline, and until this
/// normalisation they were matching whatever line ending that particular
/// region of the file happened to carry. A file with mixed endings — which
/// this repository had — made them pass or fail on an invisible property of
/// the bytes rather than on the code they are there to pin.
String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('a failed feed page is not a crash', () {
    // `_fetchLock` is read only as a boolean ("is a page in flight?"): nothing
    // awaits its future. Completing it with an error therefore produced a
    // rejection with no listener, which runZonedGuarded routes to
    // AppBootstrap.reportZoneError and Crashlytics records as *fatal*. Every
    // offline scroll was booked as a crash.
    test('the in-flight guard never completes with an error', () {
      final controller = _read('lib/controller/video_controller.dart');

      expect(
        controller,
        isNot(contains('.completeError(')),
        reason: 'a rejection nobody awaits becomes an unhandled zone error',
      );
      expect(controller, contains('void _releaseFetchLock()'));
      expect(controller, contains('lock.isCompleted'));
    });
  });

  group('automatic playback recovery is budgeted', () {
    late String player;

    setUpAll(() {
      player = _read('lib/widgets/smart_video_player.dart');
    });

    // Every watchdog ends in _purgeAndReloadController, which re-arms the
    // watchdog that fired it. Uncounted, a source that can never render a
    // first frame re-downloaded itself and logged a callable every ~6s for as
    // long as it stayed on screen.
    test('recovery attempts are counted and capped', () {
      expect(player, contains('_maxAutomaticRecoveries'));
      expect(player, contains('_automaticRecoveryAttempts'));
      expect(player, contains('_automaticRecoveryExhausted'));
      expect(
        player,
        contains('_automaticRecoveryAttempts >= _maxAutomaticRecoveries'),
      );
    });

    test('exhaustion disarms the watchdogs instead of re-arming them', () {
      final exhausted = player.indexOf('_automaticRecoveryExhausted = true;');
      expect(exhausted, isNonNegative);

      final tail = player.substring(exhausted);
      expect(tail.indexOf('_stopFirstFrameWatchdog();'), isNonNegative);
      expect(tail.indexOf('_stopStallWatchdog();'), isNonNegative);
    });

    test('the budget reopens on success and on a user-asked retry', () {
      expect(player, contains('void _resetAutomaticRecoveryBudget()'));
      // Once when playback actually works, once when the widget is recycled
      // onto another video, once from the retry button.
      expect(
        '_resetAutomaticRecoveryBudget();'.allMatches(player).length,
        greaterThanOrEqualTo(3),
      );
      expect(player, contains("recoveryReason: 'manual_retry'"));
    });

    // Reported from production on 1.0.7+18: a video showed the exhausted
    // state after an upload, and the manual retry played it instantly. That is
    // the signature of three identical attempts -- VideoManager opens a cached
    // file whenever one exists and only reads `preferDownloadedFile` on a
    // cache miss, so every automatic retry re-opened the same bytes. A
    // first-frame timeout is not an init failure either, so the manager's own
    // fresh-download fallback (which needs init to *throw*) never ran.
    //
    // A budget of three is only worth three if the attempts differ.
    test('attempts escalate rather than repeating the same one', () {
      expect(player, contains('final isFirstAttempt ='));
      expect(player, contains('purgeCachedFile: !isFirstAttempt,'));
      expect(
        player,
        contains('preferDownloadedFile: isFirstAttempt && resolvedUrl.isNotEmpty,'),
        reason: 'later attempts must stream, which is what the manual retry does',
      );
    });

    test('purging a cached video drops its cache entry, not just the bytes', () {
      expect(player, contains('VideoCacheManager.removeCachedFile(cacheUrl)'));
    });

    test('giving up shows the error state, not an endless spinner', () {
      expect(
        player,
        contains(
          'final errorMessage = _automaticRecoveryExhausted\n'
          '            ? VideoUiStrings.playbackInterruptedRetry',
        ),
      );
    });
  });

  group('a user-visible action always ends somewhere', () {
    test('video actions carry a deadline over the whole retry chain', () {
      final service = _read('lib/services/videos/video_action_service.dart');

      // The 10s HttpsCallableOptions timeout bounds one invocation.
      // callDataWithHttpFallback layers a token warm-up, a call, a forced
      // refresh, a second call and a direct HTTPS fallback on top of it.
      expect(service, contains('_actionTimeout'));
      expect(service, contains('.timeout(_actionTimeout)'));
      expect(service, contains('on TimeoutException'));
      expect(service, contains('VideoUiStrings.actionTimedOut'));
    });

    test('password reset and verification resend are bounded like sign-in', () {
      final service = _read('lib/services/auth/auth_session_service.dart');

      expect(service, contains("_bounded(send, 'réinitialisation du mot de "));
      expect(service, contains("_bounded(send, 'envoi de l’e-mail de "));
    });
  });

  group('the upload flow finishes exactly once', () {
    test('the optimization watch cannot be closed twice', () {
      final controller = _read('lib/controller/upload_video_controller.dart');

      // `completer.isCompleted` could not arbitrate: the completer is only
      // completed after `await callback()`, so a second closer arriving during
      // that await passed the guard and fired a second toast and a second
      // Get.offAllNamed.
      expect(controller, contains('var isClosingOptimization = false;'));
      expect(
        controller,
        contains('if (isClosingOptimization || completer.isCompleted) return;'),
      );
      expect(controller, contains('isClosingOptimization = true;'));
    });
  });

  group('the upload client survives what the network does to it', () {
    late String client;

    setUpAll(() {
      client = _read('lib/services/videos/data/upload_client.dart');
    });

    test('a dead resumable session is renegotiated, not retried', () {
      // validateStatus lets anything under 500 through, so Google's 404/410
      // "this session is gone" arrived as an unexpected status, was retried
      // four times against a URL that will never answer again, and failed the
      // upload. Only clock-based expiry was handled.
      expect(client, contains('_sessionGoneStatuses'));
      expect(client, contains('{404, 410}'));
      expect(client, contains('sessionRefreshCount >= _maxSessionRefreshes'));
      expect(client, contains('current = await refreshSession(current);'));
    });

    test('callable payloads are validated instead of blind-cast', () {
      // UploadSessionState's fields are non-nullable: a truncated payload used
      // to surface as a raw TypeError the error mapper could not translate.
      expect(client, contains('static String _requireString('));
      expect(client, contains('static int _requireEpochMs('));
      expect(client, isNot(contains("sessionId: data['sessionId'],")));
      expect(client, isNot(contains("uploadUrl: data['uploadUrl'],")));
      expect(
        client,
        isNot(
          contains("DateTime.fromMillisecondsSinceEpoch(data['expiresAt'])"),
        ),
      );
    });
  });

  group('sign-in spends no time on work that cannot succeed', () {
    test('the verified-state repair is skipped when Auth says unverified', () {
      final service = _read('lib/services/auth/auth_session_service.dart');

      // completeEmailVerification's first check is auth.getUser().emailVerified
      // and it answers failed-precondition when that is false — a code this
      // client treats as retriable. The repair therefore spent its whole
      // budget on guaranteed refusals on every unverified sign-in and cold
      // start, and filled the Functions log with them.
      final guard = service.indexOf('if (!isCurrentUserEmailVerified) {');
      final deadline = service.indexOf('final deadline = DateTime.now().add(');

      expect(guard, isNonNegative);
      expect(deadline, isNonNegative);
      expect(
        guard,
        lessThan(deadline),
        reason: 'the early-out must come before the retry loop it skips',
      );
    });
  });

  group('reporting cannot destroy what it reports on', () {
    test('a failed image is recorded as non-fatal, without a remote log', () {
      final bootstrap = _read('lib/config/app_bootstrap.dart');

      // Flutter reports image failures through FlutterError with
      // `library: 'image resource service'` whenever no error listener is
      // attached, and this app wires FlutterError.onError to
      // recordFlutterFatalError. A deleted profile photo counted as a crash.
      expect(bootstrap, contains('static bool _isImageResourceFailure('));
      expect(
        bootstrap,
        contains("details.library == 'image resource service'"),
      );
      expect(bootstrap, contains('if (_isImageResourceFailure(details)) {'));
      expect(bootstrap, contains('fatal: false,'));
    });

    test('no avatar loads an image without an error listener', () {
      // `CircleAvatar(backgroundImage: NetworkImage(...))` builds a
      // DecorationImage with no onError, which is exactly the unlistened case
      // above — and it left an empty circle rather than the fallback.
      const avatarWidget = 'ad_avatar.dart';

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // The one place allowed to talk to an ImageProvider directly: it is
        // the file that attaches the error listener.
        if (entity.path.endsWith(avatarWidget)) continue;

        final source = entity.readAsStringSync();
        // Lookbehind so CachedNetworkImage / CachedNetworkImageProvider, which
        // carry their own error handling, are not caught by the suffix.
        expect(
          RegExp(r'(?<![A-Za-z])NetworkImage\(').hasMatch(source),
          isFalse,
          reason: '${entity.path} must go through AdAvatar',
        );
      }
    });

    test('the avatar widget falls back instead of staying blank', () {
      final avatar = _read('lib/widgets/ad_avatar.dart');

      expect(avatar, contains('onBackgroundImageError:'));
      expect(avatar, contains('CachedNetworkImageProvider'));
      expect(avatar, contains('_loadFailed'));
    });

    test('the client log buffer is capped', () {
      final logger = _read('lib/services/client_logger.dart');

      // A failed flush puts its whole batch back at the head of the queue, and
      // the flush that fails is the one running on a broken network — where
      // new entries keep arriving because everything else is failing too.
      expect(logger, contains('_maxBufferedEntries'));
      expect(logger, contains('void _trimBuffer()'));
    });
  });

  group('one stuck download cannot freeze video playback', () {
    test('waiting for an init slot has a deadline', () {
      final manager = _read('lib/videos/video_manager.dart');

      // The slot is released by whenComplete, and loadVideo() can include a
      // downloadFile of up to 150 MB through HttpFileService, which sets no
      // socket deadline. On a low-tier network _maxConcurrentInits is 1, so
      // one stalled connection blocked every later init in the app.
      expect(manager, contains('_initSlotWaitTimeout'));
      expect(manager, contains('final slotDeadline = DateTime.now().add('));
      expect(
        manager,
        isNot(
          contains(
            'while (_activeInits >= _maxConcurrentInits) {\n'
            '        await Future.delayed(const Duration(milliseconds: 80));',
          ),
        ),
        reason: 'the unbounded busy-wait is the bug',
      );
    });

    // Two callers ask for the active video at the same moment: the
    // orchestrator from onIndexChanged, and the tile from
    // _attachOrInitialize. With the slot wait sitting between the in-flight
    // check and the registration, both found nothing registered, both
    // blocked, and both started a player when a slot freed. The second
    // overwrote lru[cacheKey], leaving the first native player reachable
    // from no map at all: never disposed, never counted against either
    // budget, holding a MediaCodec instance for the rest of the session.
    // The invariant above held only while the video on screen had not been
    // preloaded first -- which is the one case the preload exists to make
    // fast. Step (2) of the pipeline hands the active request the preload's
    // future, and with it the preload's place in a queue that allows a 20 s
    // wait. The wait then belongs to the video the user is looking at.
    test('a preload the user swiped onto stops waiting for a slot', () {
      final manager = _read('lib/videos/video_manager.dart');
      final registry = _read('lib/videos/domain/active_init_registry.dart');

      expect(registry, contains('class ActiveInitRegistry'));
      expect(registry, contains('void claim(String contextKey, String url)'));
      expect(registry, contains('bool isClaimed(String contextKey, String url)'));
      expect(registry, contains('void release(String contextKey, String url)'));

      // Claimed before `attempt` can await anything -- a preload suspended in
      // the slot queue polls for it -- and released whichever way the
      // candidate ends. A claim that outlived its request would let every
      // later preload of that URL skip the queue for the rest of the session.
      final claim = manager.indexOf('_activeInitClaims.claim(contextKey, effectiveUrl);');
      final call = manager.indexOf('final player = await attempt(');
      final release = manager.indexOf('_activeInitClaims.release(contextKey, effectiveUrl);');
      expect(claim, isNonNegative);
      expect(call, isNonNegative);
      expect(release, isNonNegative);
      expect(claim, lessThan(call), reason: 'the claim must precede the await');
      expect(
        manager.substring(release - 120, release),
        contains('} finally {'),
        reason: 'released on every exit, including the error paths',
      );

      // And read inside the wait it is meant to end.
      final loop = manager.indexOf(
        'while (_activeInits >= _maxConcurrentInits)',
      );
      final take = manager.indexOf('_activeInits++;');
      final read = manager.indexOf(
        'if (_activeInitClaims.isClaimed(contextKey, cacheKey)) {',
      );
      expect(read, isNonNegative);
      expect(loop, lessThan(read));
      expect(read, lessThan(take));
    });

    test('an in-flight init is claimed before it queues', () {
      final manager = _read('lib/videos/video_manager.dart');

      expect(manager, contains('Future<CachedVideoPlayerPlus> queueThenLoad()'));

      final claim = manager.indexOf('futures[cacheKey] = future;');
      final wait = manager.indexOf('while (_activeInits >= _maxConcurrentInits)');
      expect(claim, isNonNegative);
      expect(wait, isNonNegative);
      expect(
        wait,
        lessThan(claim),
        reason: 'the wait must live inside the future being registered, so '
            'the registration itself stays synchronous',
      );

      // A preload's init downloads the whole file before it opens anything,
      // and both it and the active video used the same queue -- two slots on
      // a medium tier, one on a low tier. adfoot-production, 2026-08-23 at
      // 17:21: a 1080p video reported `loadState: "loading"` for 25 s with no
      // init error, because nothing had failed. It had not started.
      expect(
        manager,
        contains('if (isPreload) {'),
        reason: 'only background work queues for a slot',
      );
      final gate = manager.indexOf('if (isPreload) {');
      final loop = manager.indexOf('while (_activeInits >= _maxConcurrentInits)');
      final take = manager.indexOf('_activeInits++;');
      expect(gate, isNonNegative);
      expect(gate, lessThan(loop), reason: 'the wait is what is gated');
      expect(
        loop,
        lessThan(take),
        reason: 'an active init still takes a slot, so preloads back off for '
            'it -- it just never waits for one',
      );

      // Nothing may suspend between starting the load and claiming the key:
      // the two statements have to be neighbours.
      final started = manager.indexOf('final future = queueThenLoad();');
      expect(started, isNonNegative);
      expect(
        manager.substring(started, started + 80),
        contains('futures[cacheKey] = future;'),
        reason: 'anything between these two reopens the double-init race',
      );
    });
  });
}
