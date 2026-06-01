import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_environment.dart';

class CallableAuthGuard {
  CallableAuthGuard._();

  static const bool _appCheckEnabled =
      bool.fromEnvironment('APP_CHECK_ENABLED', defaultValue: false);
  static const bool _forceAppCheckDebugProvider =
      bool.fromEnvironment('APP_CHECK_DEBUG_PROVIDER', defaultValue: false);
  static const String _androidProviderName =
      String.fromEnvironment('APP_CHECK_ANDROID_PROVIDER');
  static bool get _shouldReadAppCheckToken =>
      _appCheckEnabled ||
      _forceAppCheckDebugProvider ||
      _androidProviderName.trim().toLowerCase() == 'debug';

  static Future<void> prepareCall({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await user.getIdToken(forceRefresh);
    }

    await _readAppCheckToken(forceRefresh: forceRefresh);
  }

  static Future<HttpsCallableResult<T>> call<T>(
    HttpsCallable callable, [
    dynamic parameters,
  ]) async {
    await prepareCall();

    try {
      return await callable.call<T>(parameters);
    } on FirebaseFunctionsException catch (error) {
      if (!_shouldRetry(error)) {
        rethrow;
      }

      await prepareCall(forceRefresh: true);
      return callable.call<T>(parameters);
    }
  }

  static Future<T> callDataWithHttpFallback<T>(
    HttpsCallable callable,
    String callableName, [
    dynamic parameters,
    http.Client? httpClient,
  ]) async {
    await prepareCall();

    try {
      final result = await callable.call<T>(parameters);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      if (!_shouldRetry(error)) {
        rethrow;
      }

      await prepareCall(forceRefresh: true);

      try {
        final result = await callable.call<T>(parameters);
        return result.data;
      } on FirebaseFunctionsException catch (retryError) {
        if (!_shouldRetry(retryError)) {
          rethrow;
        }
      }

      return _callHttpsEndpoint<T>(
        callableName,
        parameters,
        httpClient: httpClient,
      );
    }
  }

  static bool _shouldRetry(FirebaseFunctionsException error) {
    return error.code == 'unauthenticated';
  }

  static Future<T> _callHttpsEndpoint<T>(
    String callableName,
    dynamic parameters, {
    http.Client? httpClient,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw _DirectCallableException(
        code: 'unauthenticated',
        message: 'Authentification requise.',
      );
    }
    final appCheckToken = await _readAppCheckToken(forceRefresh: true);
    if (_appCheckEnabled && appCheckToken == null) {
      throw _DirectCallableException(
        code: 'failed-precondition',
        message: 'Vérification de sécurité indisponible. Vérifiez App Check, '
            "redémarrez l'application puis réessayez.",
      );
    }

    final client = httpClient ?? http.Client();
    final shouldCloseClient = httpClient == null;

    try {
      final response = await client.post(
        _callableUri(callableName),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          if (appCheckToken != null) 'X-Firebase-AppCheck': appCheckToken,
        },
        body: jsonEncode({'data': parameters ?? <String, dynamic>{}}),
      );

      return _readDirectCallableResult<T>(
        response,
        callableName,
      );
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }

  @visibleForTesting
  static T readDirectCallableResultForTest<T>(
    http.Response response,
    String callableName,
  ) {
    return _readDirectCallableResult<T>(response, callableName);
  }

  static T _readDirectCallableResult<T>(
    http.Response response,
    String callableName,
  ) {
    final decoded = _decodeDirectCallableResponse(
      response,
      callableName,
    );

    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      throw _DirectCallableException(
        code: _normalizeCallableErrorCode(error['status']),
        message: (error['message'] as String?) ?? 'Erreur serveur.',
        details: error['details'],
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _DirectCallableException(
        code: _httpStatusToFunctionsCode(response.statusCode),
        message: 'Erreur serveur (${response.statusCode}).',
      );
    }

    return decoded['result'] as T;
  }

  static Map<String, dynamic> _decodeDirectCallableResponse(
    http.Response response,
    String callableName,
  ) {
    if (response.body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      throw _DirectCallableException(
        code: _httpStatusToFunctionsCode(response.statusCode),
        message: 'Réponse serveur invalide pendant l’appel $callableName.',
      );
    } on FormatException {
      final statusCode = response.statusCode;
      final code = _httpStatusToFunctionsCode(statusCode);
      throw _DirectCallableException(
        code: code,
        message: 'Service serveur indisponible pendant l appel $callableName '
            '(HTTP $statusCode).',
      );
    }
  }

  static Uri _callableUri(String callableName) {
    if (AppEnvironmentConfig.useFirebaseEmulators) {
      return Uri(
        scheme: 'http',
        host: AppEnvironmentConfig.firebaseEmulatorHost,
        port: AppEnvironmentConfig.functionsEmulatorPort,
        path: '/${AppEnvironmentConfig.firebaseProjectId}/'
            '${AppEnvironmentConfig.functionsRegion}/$callableName',
      );
    }

    return Uri.https(
      '${AppEnvironmentConfig.functionsRegion}-'
          '${AppEnvironmentConfig.firebaseProjectId}.cloudfunctions.net',
      '/$callableName',
    );
  }

  static Future<String?> _readAppCheckToken({
    bool forceRefresh = false,
  }) async {
    if (!_shouldReadAppCheckToken) {
      return null;
    }

    try {
      final token = await FirebaseAppCheck.instance.getToken(forceRefresh);
      final trimmed = token?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[CallableAuthGuard] App Check token unavailable: $error');
      }
      return null;
    }
  }

  static String _normalizeCallableErrorCode(dynamic rawStatus) {
    final status = (rawStatus as String? ?? '').trim().toUpperCase();
    switch (status) {
      case 'UNAUTHENTICATED':
        return 'unauthenticated';
      case 'PERMISSION_DENIED':
        return 'permission-denied';
      case 'FAILED_PRECONDITION':
        return 'failed-precondition';
      case 'RESOURCE_EXHAUSTED':
        return 'resource-exhausted';
      case 'INVALID_ARGUMENT':
        return 'invalid-argument';
      case 'NOT_FOUND':
        return 'not-found';
      case 'DEADLINE_EXCEEDED':
        return 'deadline-exceeded';
      default:
        return status.isEmpty ? 'unknown' : status.toLowerCase();
    }
  }

  static String _httpStatusToFunctionsCode(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'invalid-argument';
      case 401:
        return 'unauthenticated';
      case 403:
        return 'permission-denied';
      case 404:
        return 'not-found';
      case 429:
        return 'resource-exhausted';
      default:
        return 'unknown';
    }
  }
}

class _DirectCallableException extends FirebaseFunctionsException {
  _DirectCallableException({
    required super.code,
    required super.message,
    super.details,
  });
}
