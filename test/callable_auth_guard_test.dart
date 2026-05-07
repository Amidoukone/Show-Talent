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

    test('keeps callable JSON errors as FirebaseFunctionsException', () {
      final response = http.Response(
        '{"error":{"status":"PERMISSION_DENIED","message":"Acces refuse."}}',
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
              .having((error) => error.message, 'message', 'Acces refuse.'),
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
