import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// `developer.log` writes to an attached debugger and nowhere else. It reaches
/// neither `client_logs` nor Crashlytics, so anything reported only that way
/// is invisible on a real device — worse than `AppLogger.debug`, which at
/// least reads as a debug trace to whoever finds it.
///
/// The architecture guardrails ban `debugPrint(` and `print(` but not this,
/// and that gap is what let a real defect hide: the offers stream could die,
/// leaving the tab frozen for the rest of the session, and the only record
/// went to a debugger nobody had attached.
void main() {
  // AppLogger itself is built on developer.log — that is how it writes the
  // local trace — and App Check deliberately keeps its own noise local
  // (MOBILE_APPCHECK_VALIDATION_RUNBOOK), as does one documented non-blocking
  // auth warm-up. Everything else has to reach a sink that leaves the device.
  const allowed = <String>{
    'lib/services/app_logger.dart',
    'lib/services/app_check_service.dart',
    'lib/services/users/profile_repository.dart',
  };

  test('no controller reports through developer.log', () {
    final offenders = <String>[];

    for (final entity in Directory('lib/controller').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.split(Platform.pathSeparator).join('/');
      if (entity.readAsStringSync().contains('developer.log(')) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'a controller failure that never leaves the device is invisible',
    );
  });

  test('the remaining developer.log sites are the documented ones', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.split(Platform.pathSeparator).join('/');
      if (allowed.contains(path)) continue;
      if (entity.readAsStringSync().contains('developer.log(')) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'route it through AppLogger, or add it to the allow list with '
          'a reason',
    );
  });

  // A document that stops parsing does not raise anything: it is dropped, and
  // the person or the offer simply is not there any more. These three sites
  // are the only ones that know why.
  group('a silently dropped document says so', () {
    test('an offer that does not parse is reported', () {
      final offers = _read('lib/services/offers/offer_repository.dart');
      expect(offers, contains("source: 'offers/parse'"));
      expect(offers, contains('AppLogger.warning('));
    });

    test('a profile that does not parse is reported', () {
      final profile = _read('lib/services/users/profile_repository.dart');
      expect(profile, contains("source: 'profile/parse'"));

      final users = _read('lib/services/users/user_repository.dart');
      expect(users, contains('AppLogger.warning('));
    });

    // Events are the newest of the three and were the last still dropping in
    // silence: an organiser whose detection vanished from the tab had nothing
    // to report but its absence.
    test('an event that does not parse is reported', () {
      final events = _read('lib/services/events/event_repository.dart');
      expect(events, contains("source: 'events/parse'"));
      expect(events, contains('AppLogger.warning('));
    });

    // Sampled at 15%, because the snapshot re-delivers on every change and a
    // permanently malformed document would otherwise log on every update.
    test('they are warnings, not errors, so a bad document cannot flood', () {
      final offers = _read('lib/services/offers/offer_repository.dart');
      final parse = offers.indexOf("source: 'offers/parse'");
      expect(parse, isNonNegative);
      expect(
        offers.substring(parse - 300, parse),
        contains('AppLogger.warning('),
      );
    });
  });

  // `AppLogger.debug` reads like a log and is not one: `_shouldSendToRemote`
  // returns false for `debug` unconditionally, so in a release build the call
  // reaches `developer.log` and stops there. Inside a `catch`, that is the same
  // defect the group above was written for — a failure the user lives through
  // and nobody can see — only spelled with the logger instead of around it.
  //
  // Events and chat were converted first because they own the failures a
  // person actually meets: an inscription that does not take, a message that
  // does not leave. Session, profile, video, upload, follow and push followed:
  // a sign-in that drops, a profile that will not save, a feed that stops
  // paginating and an upload that never finishes are all failures the user
  // lives through, and none of them left a trace before.
  //
  // The list is the point: it only ever shrinks, and a new file may not join
  // it. What is left is one deliberate exception — ConnectivityService funnels
  // every trace through a single `_debugLog` helper that returns early unless
  // `kDebugMode`, so its debt is one decision to take, not scattered sites to
  // find.
  group('a failure the user lives through is not logged at debug', () {
    const notYetConverted = <String>{
      'lib/controller/connectivity_controller.dart',
    };

    /// Every `AppLogger.debug` whose nearest preceding `catch` is close enough
    /// above it to be the block it sits in.
    List<int> debugCallsInsideCatch(String source) {
      final lines = source.split('\n');
      final offenders = <int>[];
      var lastCatch = -1;

      for (var index = 0; index < lines.length; index += 1) {
        final line = lines[index];
        if (line.contains('catch (') || line.contains('.catchError(')) {
          lastCatch = index;
        }
        if (line.contains('AppLogger.debug(') &&
            lastCatch >= 0 &&
            index - lastCatch <= 8) {
          offenders.add(index + 1);
        }
      }
      return offenders;
    }

    Iterable<File> controllerFiles() sync* {
      for (final entity in Directory('lib/controller').listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) yield entity;
      }
    }

    String repoPath(File file) =>
        file.path.split(Platform.pathSeparator).join('/');

    test('a converted controller never falls back to debug', () {
      final offenders = <String>[];

      for (final file in controllerFiles()) {
        final path = repoPath(file);
        if (notYetConverted.contains(path)) continue;

        final lines = debugCallsInsideCatch(file.readAsStringSync());
        if (lines.isNotEmpty) {
          offenders.add('$path:${lines.join(',')}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'report it with AppLogger.warning so it reaches client_logs, '
            'the way OffreController and EventController do',
      );
    });

    test('the debt list names only files that still carry the debt', () {
      final stale = <String>[];

      for (final path in notYetConverted) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path no longer exists');
        if (debugCallsInsideCatch(file.readAsStringSync()).isEmpty) {
          stale.add(path);
        }
      }

      expect(
        stale,
        isEmpty,
        reason: 'these are converted now — remove them from notYetConverted '
            'so the guardrail starts holding them',
      );
    });
  });
}
