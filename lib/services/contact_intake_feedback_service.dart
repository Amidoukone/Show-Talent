import 'package:cloud_functions/cloud_functions.dart';

import '../config/app_environment.dart';
import 'callable_auth_guard.dart';

class ContactIntakeFeedbackStatus {
  ContactIntakeFeedbackStatus._();

  static const String noResponse = 'no_response';
  static const String discussionStarted = 'discussion_started';
  static const String trialScheduled = 'trial_scheduled';
  static const String opportunitySerious = 'opportunity_serious';
  static const String notRelevant = 'not_relevant';
  static const String issueReported = 'issue_reported';

  static const List<String> values = <String>[
    noResponse,
    discussionStarted,
    trialScheduled,
    opportunitySerious,
    notRelevant,
    issueReported,
  ];

  static String normalize(String? value) {
    switch (value?.trim().toLowerCase()) {
      case discussionStarted:
        return discussionStarted;
      case trialScheduled:
        return trialScheduled;
      case opportunitySerious:
        return opportunitySerious;
      case notRelevant:
        return notRelevant;
      case issueReported:
        return issueReported;
      case noResponse:
      default:
        return noResponse;
    }
  }

  static String label(String? value) {
    switch (normalize(value)) {
      case discussionStarted:
        return 'Discussion engagée';
      case trialScheduled:
        return 'Essai / rendez-vous prévu';
      case opportunitySerious:
        return 'Opportunité sérieuse';
      case notRelevant:
        return 'Non pertinent';
      case issueReported:
        return 'Problème signalé';
      case noResponse:
      default:
        return 'Pas encore de réponse';
    }
  }
}

class ContactIntakeFeedbackResult {
  const ContactIntakeFeedbackResult({
    required this.success,
    required this.message,
    this.code = 'unknown',
    this.status,
    this.suggestedAgencyFollowUpStatus,
  });

  final bool success;
  final String code;
  final String message;
  final String? status;
  final String? suggestedAgencyFollowUpStatus;

  factory ContactIntakeFeedbackResult.fromMap(Map<String, dynamic> map) {
    final data = map['data'];
    final payload = data is Map<String, dynamic>
        ? data
        : data is Map
            ? Map<String, dynamic>.from(data)
            : const <String, dynamic>{};

    return ContactIntakeFeedbackResult(
      success: map['success'] == true,
      code: map['code']?.toString() ?? 'unknown',
      message: map['message']?.toString() ??
          'Retour de mise en relation enregistré.',
      status: payload['status']?.toString(),
      suggestedAgencyFollowUpStatus:
          payload['suggestedAgencyFollowUpStatus']?.toString(),
    );
  }

  factory ContactIntakeFeedbackResult.failure(String message) {
    return ContactIntakeFeedbackResult(
      success: false,
      code: 'action_failed',
      message: message,
    );
  }
}

class ContactIntakeFeedbackService {
  ContactIntakeFeedbackService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(
              region: AppEnvironmentConfig.functionsRegion,
            );

  final FirebaseFunctions _functions;

  Future<ContactIntakeFeedbackResult> submitFeedback({
    required String contactIntakeId,
    required String status,
    String note = '',
    String? conversationId,
  }) async {
    final normalizedIntakeId = contactIntakeId.trim();
    final normalizedStatus = ContactIntakeFeedbackStatus.normalize(status);
    final normalizedNote = note.trim();

    if (normalizedIntakeId.isEmpty) {
      return ContactIntakeFeedbackResult.failure(
        'Mise en relation introuvable.',
      );
    }

    try {
      final callable = _functions.httpsCallable('submitContactIntakeFeedback');
      final result = await CallableAuthGuard.call<dynamic>(
        callable,
        <String, dynamic>{
          'contactIntakeId': normalizedIntakeId,
          'status': normalizedStatus,
          'note': normalizedNote,
          if (conversationId?.trim().isNotEmpty == true)
            'conversationId': conversationId!.trim(),
        },
      );
      final data = result.data;
      final map = data is Map<String, dynamic>
          ? data
          : data is Map
              ? Map<String, dynamic>.from(data)
              : <String, dynamic>{};
      return ContactIntakeFeedbackResult.fromMap(map);
    } on FirebaseFunctionsException catch (error) {
      return ContactIntakeFeedbackResult.failure(
        _mapFunctionsError(error),
      );
    } catch (_) {
      return ContactIntakeFeedbackResult.failure(
        'Retour impossible pour le moment. Réessayez plus tard.',
      );
    }
  }

  String _mapFunctionsError(FirebaseFunctionsException error) {
    final message = error.message?.trim();
    final normalizedCode = error.code.trim().toUpperCase().replaceAll('-', '_');
    final normalizedMessage = message?.toUpperCase();
    if (message != null &&
        message.isNotEmpty &&
        message.toLowerCase() != 'internal' &&
        normalizedMessage != normalizedCode) {
      return message;
    }

    switch (error.code) {
      case 'unauthenticated':
        return 'Session expirée. Reconnectez-vous.';
      case 'permission-denied':
        return 'Seuls les participants peuvent envoyer ce retour.';
      case 'not-found':
        return 'Mise en relation introuvable.';
      case 'invalid-argument':
        return 'Retour invalide. Vérifiez les informations envoyées.';
      default:
        return 'Retour impossible pour le moment. Réessayez plus tard.';
    }
  }
}
