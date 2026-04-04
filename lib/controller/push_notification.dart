import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../config/app_environment.dart';

class PushNotificationService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: AppEnvironmentConfig.functionsRegion,
  );

  static Future<void> _invoke(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    final callable = _functions.httpsCallable(
      functionName,
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 20),
      ),
    );

    await callable.call<Map<String, dynamic>>(payload);
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

  static Future<void> sendOfferFanout({
    required String offerId,
    required String title,
    required String body,
  }) async {
    try {
      await _invoke('sendOfferFanout', {
        'offerId': offerId,
        'title': title,
        'body': body,
      });
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('sendOfferFanout error ${e.code}: ${e.message}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('sendOfferFanout unexpected error: $e');
      }
    }
  }

  static Future<void> sendEventFanout({
    required String eventId,
    required String title,
    required String body,
  }) async {
    try {
      await _invoke('sendEventFanout', {
        'eventId': eventId,
        'title': title,
        'body': body,
      });
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('sendEventFanout error ${e.code}: ${e.message}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('sendEventFanout unexpected error: $e');
      }
    }
  }
}
