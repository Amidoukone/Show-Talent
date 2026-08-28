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
}
