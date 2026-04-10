import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../config/app_environment.dart';
import '../models/action_response.dart';
import '../services/callable_auth_guard.dart';

class PushNotificationService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: AppEnvironmentConfig.functionsRegion,
  );

  static Future<Map<String, dynamic>?> _invoke(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    final callable = _functions.httpsCallable(
      functionName,
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 20),
      ),
    );

    final result = await CallableAuthGuard.call<Map<String, dynamic>>(
      callable,
      payload,
    );
    return result.data;
  }

  static Future<void> sendNotification({
    required String title,
    required String body,
    required String recipientUid,
    required String contextType,
    required String contextData,
  }) async {
    try {
      await _invoke('sendUserPush', {
        'title': title,
        'body': body,
        'recipientUid': recipientUid,
        'contextType': contextType,
        'contextData': contextData,
      });
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'PushNotificationService error ${e.code}: ${e.message}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PushNotificationService unexpected error: $e');
      }
    }
  }

  static Future<ActionResponse> sendOfferFanout({
    required String offerId,
    required String title,
    required String body,
  }) async {
    try {
      final response = await _invoke('sendOfferFanout', {
        'offerId': offerId,
        'title': title,
        'body': body,
      });
      return ActionResponse.fromMap(response, toastOverride: ToastLevel.none);
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('sendOfferFanout error ${e.code}: ${e.message}');
      }
      return ActionResponse.failure(
        message: e.message ?? 'Envoi des notifications indisponible.',
        code: e.code,
        toast: ToastLevel.none,
        retriable: e.code == 'unavailable',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('sendOfferFanout unexpected error: $e');
      }
      return ActionResponse.failure(
        message: 'Envoi des notifications indisponible.',
        code: 'fanout_unavailable',
        toast: ToastLevel.none,
        retriable: true,
      );
    }
  }

  static Future<ActionResponse> sendEventFanout({
    required String eventId,
    required String title,
    required String body,
  }) async {
    try {
      final response = await _invoke('sendEventFanout', {
        'eventId': eventId,
        'title': title,
        'body': body,
      });
      return ActionResponse.fromMap(response, toastOverride: ToastLevel.none);
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('sendEventFanout error ${e.code}: ${e.message}');
      }
      return ActionResponse.failure(
        message: e.message ?? 'Envoi des notifications indisponible.',
        code: e.code,
        toast: ToastLevel.none,
        retriable: e.code == 'unavailable',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('sendEventFanout unexpected error: $e');
      }
      return ActionResponse.failure(
        message: 'Envoi des notifications indisponible.',
        code: 'fanout_unavailable',
        toast: ToastLevel.none,
        retriable: true,
      );
    }
  }
}
