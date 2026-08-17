import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import 'app_check_service.dart';
import 'package:adfoot/services/app_logger.dart';

class CallableAuthGuard {
  CallableAuthGuard._();

  static const Duration _authCachedTokenTimeout = Duration(seconds: 10);
  static const Duration _authForcedTokenTimeout = Duration(seconds: 25);
  // Tight on purpose: the App Check token is optional (see
  // _callHttpsEndpoint), so waiting long for one only adds latency to every
  // single callable on devices where attestation never succeeds. These used
  // to be 10s/25s, which stacked on top of the auth token wait and made a
  // failing upload take close to a minute before showing an error.
  static const Duration _appCheckCachedTokenTimeout = Duration(seconds: 3);
  static const Duration _appCheckForcedTokenTimeout = Duration(seconds: 6);
  static const Duration _directCallableTimeout = Duration(seconds: 50);

  static const bool _configuredAppCheckEnabled = bool.fromEnvironment(
    'APP_CHECK_ENABLED',
    defaultValue: false,
  );
  static const bool _forceAppCheckDebugProvider = bool.fromEnvironment(
    'APP_CHECK_DEBUG_PROVIDER',
    defaultValue: false,
  );
  static const String _androidProviderName = String.fromEnvironment(
    'APP_CHECK_ANDROID_PROVIDER',
  );
  static bool get _appCheckEnabled =>
      _configuredAppCheckEnabled || AppEnvironmentConfig.isProduction;
  static bool get _shouldReadAppCheckToken =>
      _appCheckEnabled ||
      _forceAppCheckDebugProvider ||
      _androidProviderName.trim().toLowerCase() == 'debug';

  static Future<void> prepareCall({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _readAuthToken(user, forceRefresh: forceRefresh);
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
    switch (error.code) {
      case 'unauthenticated':
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
      case 'aborted':
      case 'cancelled':
        return true;
      default:
        return false;
    }
  }

  static Future<T> _callHttpsEndpoint<T>(
    String callableName,
    dynamic parameters, {
    http.Client? httpClient,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await _readRequiredAuthToken(user);
    if (token == null || token.isEmpty) {
      throw _DirectCallableException(
        code: 'unauthenticated',
        message: 'Authentification requise.',
      );
    }
    // Opportunistic: the header is attached when attestation succeeded, and
    // omitted otherwise. It must never decide whether the request is sent.
    // Refusing here turned every device that can't run Play Integrity into a
    // device that can't upload a video, post a like or follow anyone —
    // while the backend itself (see functions/src/function_runtime.ts) only
    // treats App Check as an anti-abuse signal, with authentication and
    // authorization enforced separately on every callable.
    final appCheckToken = await _readAppCheckToken();

    final client = httpClient ?? http.Client();
    final shouldCloseClient = httpClient == null;

    try {
      final response = await client
          .post(
            _callableUri(callableName),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'X-Firebase-AppCheck': ?appCheckToken,
            },
            body: jsonEncode({'data': parameters ?? <String, dynamic>{}}),
          )
          .timeout(_directCallableTimeout);

      return _readDirectCallableResult<T>(response, callableName);
    } on TimeoutException {
      throw _DirectCallableException(
        code: 'deadline-exceeded',
        message:
            'Le serveur met trop de temps à répondre. Vérifiez votre réseau '
            'puis réessayez.',
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
    final decoded = _decodeDirectCallableResponse(response, callableName);

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
        message:
            'Service serveur indisponible pendant l appel $callableName '
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
        path:
            '/${AppEnvironmentConfig.firebaseProjectId}/'
            '${AppEnvironmentConfig.functionsRegion}/$callableName',
      );
    }

    return Uri.https(
      '${AppEnvironmentConfig.functionsRegion}-'
          '${AppEnvironmentConfig.firebaseProjectId}.cloudfunctions.net',
      '/$callableName',
    );
  }

  static Future<void> _readAuthToken(
    User user, {
    required bool forceRefresh,
  }) async {
    try {
      await user
          .getIdToken(forceRefresh)
          .timeout(
            forceRefresh ? _authForcedTokenTimeout : _authCachedTokenTimeout,
          );
    } on TimeoutException catch (error) {
      if (kDebugMode) {
        AppLogger.debug(
          '[CallableAuthGuard] Auth token warm-up timed out: $error',
        );
      }
    } on FirebaseAuthException catch (error) {
      if (!_isTransientAuthError(error)) {
        rethrow;
      }
      if (kDebugMode) {
        AppLogger.debug(
          '[CallableAuthGuard] Auth token warm-up failed: ${error.code}',
        );
      }
    }
  }

  static Future<String?> _readRequiredAuthToken(User? user) async {
    if (user == null) {
      return null;
    }

    final cachedToken = await _readRequiredAuthTokenAttempt(
      user,
      forceRefresh: false,
    );
    if (cachedToken != null && cachedToken.isNotEmpty) {
      return cachedToken;
    }

    return _readRequiredAuthTokenAttempt(user, forceRefresh: true);
  }

  static Future<String?> _readRequiredAuthTokenAttempt(
    User user, {
    required bool forceRefresh,
  }) async {
    try {
      final token = await user
          .getIdToken(forceRefresh)
          .timeout(
            forceRefresh ? _authForcedTokenTimeout : _authCachedTokenTimeout,
          );
      final trimmed = token?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } on TimeoutException {
      if (!forceRefresh) {
        if (kDebugMode) {
          AppLogger.debug(
            '[CallableAuthGuard] Cached auth token unavailable before '
            'HTTP fallback.',
          );
        }
        return null;
      }
      throw _DirectCallableException(
        code: 'deadline-exceeded',
        message:
            'Authentification trop longue. Vérifiez votre réseau puis '
            'réessayez.',
      );
    } on FirebaseAuthException catch (error) {
      if (!forceRefresh && _isTransientAuthError(error)) {
        if (kDebugMode) {
          AppLogger.debug(
            '[CallableAuthGuard] Cached auth token failed before HTTP '
            'fallback: ${error.code}',
          );
        }
        return null;
      }
      throw _DirectCallableException(
        code: _isTransientAuthError(error) ? 'unavailable' : 'unauthenticated',
        message:
            error.message ??
            'Authentification indisponible. Reconnectez-vous puis réessayez.',
      );
    }
  }

  static Future<String?> _readAppCheckToken({bool forceRefresh = false}) async {
    if (!_shouldReadAppCheckToken) {
      return null;
    }

    try {
      return await AppCheckService.getToken(
        forceRefresh: forceRefresh,
        timeout: forceRefresh
            ? _appCheckForcedTokenTimeout
            : _appCheckCachedTokenTimeout,
      );
    } catch (error) {
      if (kDebugMode) {
        AppLogger.debug(
          '[CallableAuthGuard] App Check token unavailable: $error',
        );
      }
      return null;
    }
  }

  static bool _isTransientAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'network-request-failed':
      case 'too-many-requests':
      case 'internal-error':
      case 'unknown':
        return true;
      default:
        return false;
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
