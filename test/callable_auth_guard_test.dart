import 'package:adfoot/services/callable_auth_guard.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

void main() {
  group('CallableAuthGuard direct HTTP response decoding', () {
    test('does not retry business permission-denied errors through raw HTTP',
        () {
      final source =
          File('lib/services/callable_auth_guard.dart').readAsStringSync();

      expect(
        source,
        contains("return error.code == 'unauthenticated';"),
      );
      expect(
        source,
        isNot(contains("error.code == 'permission-denied'")),
      );
    });

    test('keeps App Check on raw HTTP fallback for production callables', () {
      final source =
          File('lib/services/callable_auth_guard.dart').readAsStringSync();

      expect(source, contains("bool.fromEnvironment('APP_CHECK_ENABLED'"));
      expect(source, contains('FirebaseAppCheck.instance.getToken'));
      expect(source, contains('_appCheckEnabled && appCheckToken == null'));
      expect(source, contains("'X-Firebase-AppCheck': appCheckToken"));
    });

    test('keeps callable JSON errors as FirebaseFunctionsException', () {
      final response = http.Response(
        '{"error":{"status":"PERMISSION_DENIED","message":"Accès refusé."}}',
        403,
      );

      expect(
        () => CallableAuthGuard.readDirectCallableResultForTest<
            Map<String, dynamic>>(
          response,
          'createUploadSession',
        ),
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
        () => CallableAuthGuard.readDirectCallableResultForTest<
            Map<String, dynamic>>(
          response,
          'createUploadSession',
        ),
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
