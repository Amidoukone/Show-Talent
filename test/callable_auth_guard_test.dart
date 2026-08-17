import 'package:adfoot/services/callable_auth_guard.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

void main() {
  group('CallableAuthGuard direct HTTP response decoding', () {
    test(
      'does not retry business permission-denied errors through raw HTTP',
      () {
        final source = File(
          'lib/services/callable_auth_guard.dart',
        ).readAsStringSync();

        expect(source, contains("case 'unauthenticated':"));
        expect(source, contains("case 'unavailable':"));
        expect(source, contains("case 'deadline-exceeded':"));
        expect(source, isNot(contains("case 'permission-denied':")));
      },
    );

    test('attaches App Check opportunistically on the raw HTTP fallback', () {
      final source = File(
        'lib/services/callable_auth_guard.dart',
      ).readAsStringSync();
      final appCheckService = File(
        'lib/services/app_check_service.dart',
      ).readAsStringSync();

      expect(source, contains('bool.fromEnvironment('));
      expect(source, contains("'APP_CHECK_ENABLED'"));
      expect(
        source,
        contains(
          '_configuredAppCheckEnabled || AppEnvironmentConfig.isProduction',
        ),
      );
      expect(source, contains('AppCheckService.getToken'));
      expect(source, isNot(contains('FirebaseAppCheck.instance.getToken')));
      expect(appCheckService, contains('static Future<String?> getToken'));
      expect(appCheckService, contains('_activationFuture ??= _activate'));
      expect(appCheckService, contains('FirebaseAppCheck.instance'));
      expect(source, contains('_appCheckCachedTokenTimeout'));
      expect(source, contains('_appCheckForcedTokenTimeout'));
      expect(source, contains('_directCallableTimeout'));
      // A missing App Check token must never abort a call. Play Integrity
      // attestation fails outright on part of the real device fleet, and the
      // backend treats App Check as an anti-abuse signal only (see
      // functions/src/function_runtime.ts). Guard against the old
      // fail-closed shape returning.
      expect(source, isNot(contains('_appCheckEnabled && appCheckToken')));
      expect(source, isNot(contains('Connexion sécurisée indisponible')));
      expect(source, contains("'X-Firebase-AppCheck': ?appCheckToken"));
    });

    test('keeps callable JSON errors as FirebaseFunctionsException', () {
      final response = http.Response(
        '{"error":{"status":"PERMISSION_DENIED","message":"Accès refusé."}}',
        403,
      );

      expect(
        () =>
            CallableAuthGuard.readDirectCallableResultForTest<
              Map<String, dynamic>
            >(response, 'createUploadSession'),
        throwsA(
          isA<FirebaseFunctionsException>()
              .having((error) => error.code, 'code', 'permission-denied')
              .having((error) => error.message, 'message', 'Accès refusé.'),
        ),
      );
    });

    test('maps non JSON server responses to a controlled exception', () {
      final response = http.Response(
        '<!doctype html>\n<html><body>Forbidden</body></html>',
        403,
      );

      expect(
        () =>
            CallableAuthGuard.readDirectCallableResultForTest<
              Map<String, dynamic>
            >(response, 'createUploadSession'),
        throwsA(
          isA<FirebaseFunctionsException>()
              .having((error) => error.code, 'code', 'permission-denied')
              .having(
                (error) => error.message,
                'message',
                contains('Service serveur indisponible'),
              ),
        ),
      );
    });
  });
}
