import 'package:cloud_firestore/cloud_firestore.dart';

class ContactContextType {
  ContactContextType._();

  static const String none = 'none';
  static const String profile = 'profile';
  static const String event = 'event';
  static const String participants = 'participants';
  static const String discovery = 'discovery';
  static const String offer = 'offer';
}

class ContactReasonCode {
  ContactReasonCode._();

  static const String opportunity = 'opportunity';
  static const String trial = 'trial';
  static const String application = 'application';
  static const String followUp = 'follow_up';
  static const String information = 'information';
}

class ContactIntakeStatus {
  ContactIntakeStatus._();

  static const String newRequest = 'new';
}

class AgencyFollowUpStatus {
  AgencyFollowUpStatus._();

  static const String newLead = 'new';
  static const String reviewing = 'reviewing';
  static const String inProgress = 'in_progress';
  static const String qualified = 'qualified';
  static const String closed = 'closed';

  static const List<String> values = <String>[
    newLead,
    reviewing,
    inProgress,
    qualified,
    closed,
  ];
}

class ContactContext {
  const ContactContext({
    required this.type,
    this.id,
    this.title,
    this.sourceLabel,
  });

  final String type;
  final String? id;
  final String? title;
  final String? sourceLabel;

  factory ContactContext.profile({
    required String profileUid,
    String? title,
  }) {
    return ContactContext(
      type: ContactContextType.profile,
      id: profileUid.trim(),
      title: title?.trim(),
      sourceLabel: 'Profil',
    );
  }

  factory ContactContext.event({
    required String eventId,
    String? title,
    String? sourceLabel,
  }) {
    return ContactContext(
      type: ContactContextType.event,
      id: eventId.trim(),
      title: title?.trim(),
      sourceLabel: sourceLabel?.trim().isNotEmpty == true
          ? sourceLabel!.trim()
          : 'Événement',
    );
  }

  factory ContactContext.discovery({
    String? title,
  }) {
    return ContactContext(
      type: ContactContextType.discovery,
      title: title?.trim(),
      sourceLabel: 'Découverte',
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': normalizedType,
      if (normalizedId != null) 'id': normalizedId,
      if (normalizedTitle != null) 'title': normalizedTitle,
      if (normalizedSourceLabel != null) 'sourceLabel': normalizedSourceLabel,
    };
  }

  String get normalizedType {
    switch (type.trim().toLowerCase()) {
      case ContactContextType.profile:
        return ContactContextType.profile;
      case ContactContextType.event:
        return ContactContextType.event;
      case ContactContextType.participants:
        return ContactContextType.participants;
      case ContactContextType.discovery:
        return ContactContextType.discovery;
      case ContactContextType.offer:
        return ContactContextType.offer;
      default:
        return ContactContextType.none;
    }
  }

  String? get normalizedId {
    final value = id?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get normalizedTitle {
    final value = title?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get normalizedSourceLabel {
    final value = sourceLabel?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String get displayLabel {
    return labelForType(normalizedType);
  }

  static String labelForType(String? type) {
    switch (type?.trim().toLowerCase()) {
      case ContactContextType.profile:
        return 'Profil';
      case ContactContextType.event:
        return 'Événement';
      case ContactContextType.participants:
        return 'Participants';
      case ContactContextType.discovery:
        return 'Découverte';
      case ContactContextType.offer:
        return 'Offre';
      default:
        return 'Contact';
    }
  }
}

class GuidedContactDraft {
  const GuidedContactDraft({
    required this.context,
    required this.reasonCode,
    required this.introMessage,
  });

  final ContactContext context;
  final String reasonCode;
  final String introMessage;
}

class ContactIntake {
  const ContactIntake({
    required this.id,
    required this.requesterUid,
    required this.targetUid,
    required this.requesterRole,
    required this.targetRole,
    required this.contextType,
    required this.contactReason,
    required this.introMessage,
    required this.status,
    required this.agencyFollowUpStatus,
    this.agencyFollowUpNote,
    this.agencyLastUpdatedByUid,
    this.agencyLastUpdatedAt,
    this.conversationId,
    this.contextId,
    this.contextTitle,
    this.requesterSnapshot,
    this.targetSnapshot,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String requesterUid;
  final String targetUid;
  final String requesterRole;
  final String targetRole;
  final String contextType;
  final String contactReason;
  final String introMessage;
  final String status;
  final String agencyFollowUpStatus;
  final String? agencyFollowUpNote;
  final String? agencyLastUpdatedByUid;
  final DateTime? agencyLastUpdatedAt;
  final String? conversationId;
  final String? contextId;
  final String? contextTitle;
  final Map<String, dynamic>? requesterSnapshot;
  final Map<String, dynamic>? targetSnapshot;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'requesterUid': requesterUid,
      'targetUid': targetUid,
      'requesterRole': requesterRole,
      'targetRole': targetRole,
      'contextType': ContactContext(
        type: contextType,
      ).normalizedType,
      'contactReason': normalizeReasonCode(contactReason),
      'introMessage': introMessage.trim(),
      'status': normalizeStatus(status),
      'agencyFollowUpStatus': normalizeAgencyFollowUpStatus(
        agencyFollowUpStatus,
      ),
      if (agencyFollowUpNote?.trim().isNotEmpty == true)
        'agencyFollowUpNote': agencyFollowUpNote!.trim(),
      if (agencyLastUpdatedByUid?.trim().isNotEmpty == true)
        'agencyLastUpdatedByUid': agencyLastUpdatedByUid!.trim(),
      if (agencyLastUpdatedAt != null)
        'agencyLastUpdatedAt': Timestamp.fromDate(agencyLastUpdatedAt!),
      if (conversationId?.trim().isNotEmpty == true)
        'conversationId': conversationId!.trim(),
      if (contextId?.trim().isNotEmpty == true) 'contextId': contextId!.trim(),
      if (contextTitle?.trim().isNotEmpty == true)
        'contextTitle': contextTitle!.trim(),
      if (requesterSnapshot != null) 'requesterSnapshot': requesterSnapshot,
      if (targetSnapshot != null) 'targetSnapshot': targetSnapshot,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  factory ContactIntake.fromMap(
    Map<String, dynamic> map, {
    String? fallbackId,
  }) {
    final rawId = map['id']?.toString().trim() ?? '';
    final resolvedId = rawId.isNotEmpty ? rawId : (fallbackId ?? '');

    return ContactIntake(
      id: resolvedId,
      requesterUid: map['requesterUid']?.toString() ?? '',
      targetUid: map['targetUid']?.toString() ?? '',
      requesterRole: map['requesterRole']?.toString() ?? '',
      targetRole: map['targetRole']?.toString() ?? '',
      contextType: ContactContext(type: map['contextType']?.toString() ?? '')
          .normalizedType,
      contactReason: normalizeReasonCode(map['contactReason']?.toString()),
      introMessage: map['introMessage']?.toString() ?? '',
      status: normalizeStatus(map['status']?.toString()),
      agencyFollowUpStatus: normalizeAgencyFollowUpStatus(
        map['agencyFollowUpStatus']?.toString(),
      ),
      agencyFollowUpNote: _normalizeNullableString(map['agencyFollowUpNote']),
      agencyLastUpdatedByUid:
          _normalizeNullableString(map['agencyLastUpdatedByUid']),
      agencyLastUpdatedAt: _parseNullableDate(map['agencyLastUpdatedAt']),
      conversationId: _normalizeNullableString(map['conversationId']),
      contextId: _normalizeNullableString(map['contextId']),
      contextTitle: _normalizeNullableString(map['contextTitle']),
      requesterSnapshot: _normalizeMap(map['requesterSnapshot']),
      targetSnapshot: _normalizeMap(map['targetSnapshot']),
      createdAt: _parseNullableDate(map['createdAt']),
      updatedAt: _parseNullableDate(map['updatedAt']),
    );
  }

  static String normalizeReasonCode(String? value) {
    final normalized = value?.trim().toLowerCase();
    switch (normalized) {
      case ContactReasonCode.opportunity:
        return ContactReasonCode.opportunity;
      case ContactReasonCode.trial:
        return ContactReasonCode.trial;
      case ContactReasonCode.application:
        return ContactReasonCode.application;
      case ContactReasonCode.followUp:
        return ContactReasonCode.followUp;
      default:
        return ContactReasonCode.information;
    }
  }

  static String normalizeStatus(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == ContactIntakeStatus.newRequest
        ? ContactIntakeStatus.newRequest
        : ContactIntakeStatus.newRequest;
  }

  static String normalizeAgencyFollowUpStatus(String? value) {
    switch (value?.trim().toLowerCase()) {
      case AgencyFollowUpStatus.reviewing:
        return AgencyFollowUpStatus.reviewing;
      case AgencyFollowUpStatus.inProgress:
        return AgencyFollowUpStatus.inProgress;
      case AgencyFollowUpStatus.qualified:
        return AgencyFollowUpStatus.qualified;
      case AgencyFollowUpStatus.closed:
        return AgencyFollowUpStatus.closed;
      case AgencyFollowUpStatus.newLead:
      default:
        return AgencyFollowUpStatus.newLead;
    }
  }

  static String reasonLabel(String code) {
    switch (normalizeReasonCode(code)) {
      case ContactReasonCode.opportunity:
        return 'Opportunité';
      case ContactReasonCode.trial:
        return 'Essai / Évaluation';
      case ContactReasonCode.application:
        return 'Candidature / Présentation';
      case ContactReasonCode.followUp:
        return 'Suivi';
      default:
        return 'Information';
    }
  }

  static String agencyFollowUpLabel(String code) {
    switch (normalizeAgencyFollowUpStatus(code)) {
      case AgencyFollowUpStatus.reviewing:
        return 'En revue';
      case AgencyFollowUpStatus.inProgress:
        return 'En accompagnement';
      case AgencyFollowUpStatus.qualified:
        return 'Qualifié';
      case AgencyFollowUpStatus.closed:
        return 'Clos';
      case AgencyFollowUpStatus.newLead:
      default:
        return 'Nouveau lead';
    }
  }

  static Map<String, dynamic>? _normalizeMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  static String? _normalizeNullableString(dynamic value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}

class GuidedConversationStartResult {
  const GuidedConversationStartResult({
    required this.conversationId,
    required this.conversationCreated,
    this.contactIntake,
  });

  final String conversationId;
  final bool conversationCreated;
  final ContactIntake? contactIntake;

  bool get createdIntake => contactIntake != null;
}
