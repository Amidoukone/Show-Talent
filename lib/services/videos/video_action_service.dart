import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:adfoot/config/app_environment.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/services/callable_auth_guard.dart';
import 'package:adfoot/utils/video_ui_strings.dart';

class VideoActionService {
  VideoActionService({
    FirebaseFunctions? functions,
    Connectivity? connectivity,
  })  : _functions = functions ??
            FirebaseFunctions.instanceFor(
              region: AppEnvironmentConfig.functionsRegion,
            ),
        _connectivity = connectivity ?? Connectivity();

  final FirebaseFunctions _functions;
  final Connectivity _connectivity;

  Future<ActionResponse> callAction(
    String functionName,
    Map<String, dynamic> payload, {
    String? offlineMessage,
  }) async {
    try {
      if (await _isOffline()) {
        return ActionResponse.offline(offlineMessage);
      }

      final callable = _functions.httpsCallable(
        functionName,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 10),
        ),
      );

      final data = await CallableAuthGuard.callDataWithHttpFallback<
          Map<String, dynamic>>(
        callable,
        functionName,
        payload,
      );
      return ActionResponse.fromMap(data);
    } on FirebaseFunctionsException catch (error) {
      if (isAuthAccessFailure(error)) {
        return authRequiredResponse();
      }

      if (error.code == 'permission-denied') {
        return sessionRevokedResponse();
      }

      return ActionResponse.failure(
        message: error.message ?? VideoUiStrings.genericActionImpossible,
        code: error.code,
        retriable: error.code == 'unavailable',
      );
    } catch (error) {
      if (isPermissionDenied(error)) {
        return sessionRevokedResponse();
      }

      return ActionResponse.failure(
        message: VideoUiStrings.genericActionRetry,
        retriable: true,
      );
    }
  }

  Future<bool> _isOffline() async {
    try {
      final dynamic result = await _connectivity.checkConnectivity();
      if (result is ConnectivityResult) {
        return result == ConnectivityResult.none;
      }
      if (result is List<ConnectivityResult>) {
        return result.every((entry) => entry == ConnectivityResult.none);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static ActionResponse sessionRevokedResponse() {
    return const ActionResponse(
      success: false,
      code: 'session_revoked',
      message: VideoUiStrings.sessionRevokedMessage,
      toast: ToastLevel.none,
    );
  }

  static ActionResponse authRequiredResponse() {
    return const ActionResponse(
      success: false,
      code: 'unauthenticated',
      message: VideoUiStrings.authRequiredMessage,
      toast: ToastLevel.info,
      retriable: true,
    );
  }

  static bool isPermissionDenied(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }

  static bool isAuthAccessFailure(Object error) {
    if (error is! FirebaseException) {
      return false;
    }

    final code = _normalizeAuthErrorToken(error.code);
    final message = _normalizeAuthErrorToken(error.message ?? '');
    return code == 'unauthenticated' ||
        code == 'unauthentificated' ||
        message.contains('unauthenticated') ||
        message.contains('unauthentificated');
  }

  static String _normalizeAuthErrorToken(String raw) {
    return raw.trim().toLowerCase().replaceAll('_', '-');
  }
}
