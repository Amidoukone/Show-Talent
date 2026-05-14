import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for a message exchanged between two users.
class Message {
  final String id;
  final String expediteurId;
  final String destinataireId;
  final String contenu;
  final DateTime dateEnvoi;
  final bool estLu;

  Message({
    required this.id,
    required this.expediteurId,
    required this.destinataireId,
    required this.contenu,
    required this.dateEnvoi,
    required this.estLu,
  });

  Map<String, dynamic> toMap() {
    return {
      'expediteurId': expediteurId,
      'destinataireId': destinataireId,
      'contenu': contenu,
      'dateEnvoi': Timestamp.fromDate(dateEnvoi),
      'estLu': estLu,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] ?? '',
      expediteurId: map['expediteurId'] ?? '',
      destinataireId: map['destinataireId'] ?? '',
      contenu: map['contenu'] ?? '',
      dateEnvoi: (map['dateEnvoi'] as Timestamp).toDate(),
      estLu: map['estLu'] ?? false,
    );
  }
}

/// Model for a conversation between two users.
class Conversation {
  final String id;
  final String utilisateur1Id;
  final String utilisateur2Id;
  final List<String> utilisateurIds;
  Map<String, int> unreadCountByUser;
  String? lastMessage;
  DateTime? lastMessageDate;
  String? createdVia;
  String? contextType;
  String? contextId;
  String? contextTitle;
  String? contactReason;
  String? initiatedByUid;
  String? initiatedByRole;
  String? agencyFollowUpStatus;
  String? contactIntakeId;
  String? latestParticipantFeedbackStatus;
  String? latestParticipantFeedbackNote;
  String? latestParticipantFeedbackByUid;
  String? latestParticipantFeedbackByRole;
  String? suggestedAgencyFollowUpStatus;
  DateTime? latestParticipantFeedbackAt;
  DateTime? createdAt;
  int unreadMessagesCount;

  Conversation({
    required this.id,
    required this.utilisateur1Id,
    required this.utilisateur2Id,
    required this.utilisateurIds,
    this.unreadCountByUser = const {},
    this.lastMessage,
    this.lastMessageDate,
    this.createdVia,
    this.contextType,
    this.contextId,
    this.contextTitle,
    this.contactReason,
    this.initiatedByUid,
    this.initiatedByRole,
    this.agencyFollowUpStatus,
    this.contactIntakeId,
    this.latestParticipantFeedbackStatus,
    this.latestParticipantFeedbackNote,
    this.latestParticipantFeedbackByUid,
    this.latestParticipantFeedbackByRole,
    this.suggestedAgencyFollowUpStatus,
    this.latestParticipantFeedbackAt,
    this.createdAt,
    this.unreadMessagesCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'utilisateur1Id': utilisateur1Id,
      'utilisateur2Id': utilisateur2Id,
      'utilisateurIds': utilisateurIds,
      'unreadCountByUser': unreadCountByUser,
      'lastMessage': lastMessage,
      'lastMessageDate':
          lastMessageDate != null ? Timestamp.fromDate(lastMessageDate!) : null,
      'createdVia': createdVia,
      'contextType': contextType,
      'contextId': contextId,
      'contextTitle': contextTitle,
      'contactReason': contactReason,
      'initiatedByUid': initiatedByUid,
      'initiatedByRole': initiatedByRole,
      'agencyFollowUpStatus': agencyFollowUpStatus,
      'contactIntakeId': contactIntakeId,
      'latestParticipantFeedbackStatus': latestParticipantFeedbackStatus,
      'latestParticipantFeedbackNote': latestParticipantFeedbackNote,
      'latestParticipantFeedbackByUid': latestParticipantFeedbackByUid,
      'latestParticipantFeedbackByRole': latestParticipantFeedbackByRole,
      'suggestedAgencyFollowUpStatus': suggestedAgencyFollowUpStatus,
      'latestParticipantFeedbackAt': latestParticipantFeedbackAt != null
          ? Timestamp.fromDate(latestParticipantFeedbackAt!)
          : null,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> map) {
    final rawUnread = map['unreadCountByUser'];
    final unreadMap = <String, int>{};
    if (rawUnread is Map) {
      rawUnread.forEach((key, value) {
        final parsed = value is int ? value : int.tryParse('$value') ?? 0;
        unreadMap[key.toString()] = parsed;
      });
    }

    return Conversation(
      id: map['id'] ?? '',
      utilisateur1Id: map['utilisateur1Id'] ?? '',
      utilisateur2Id: map['utilisateur2Id'] ?? '',
      utilisateurIds: List<String>.from(map['utilisateurIds'] ?? []),
      unreadCountByUser: unreadMap,
      lastMessage: map['lastMessage'] ?? '',
      lastMessageDate: _parseNullableDate(map['lastMessageDate']),
      createdVia: _normalizeNullableString(map['createdVia']),
      contextType: _normalizeNullableString(map['contextType']),
      contextId: _normalizeNullableString(map['contextId']),
      contextTitle: _normalizeNullableString(map['contextTitle']),
      contactReason: _normalizeNullableString(map['contactReason']),
      initiatedByUid: _normalizeNullableString(map['initiatedByUid']),
      initiatedByRole: _normalizeNullableString(map['initiatedByRole']),
      agencyFollowUpStatus:
          _normalizeNullableString(map['agencyFollowUpStatus']),
      contactIntakeId: _normalizeNullableString(map['contactIntakeId']),
      latestParticipantFeedbackStatus:
          _normalizeNullableString(map['latestParticipantFeedbackStatus']),
      latestParticipantFeedbackNote:
          _normalizeNullableString(map['latestParticipantFeedbackNote']),
      latestParticipantFeedbackByUid:
          _normalizeNullableString(map['latestParticipantFeedbackByUid']),
      latestParticipantFeedbackByRole:
          _normalizeNullableString(map['latestParticipantFeedbackByRole']),
      suggestedAgencyFollowUpStatus:
          _normalizeNullableString(map['suggestedAgencyFollowUpStatus']),
      latestParticipantFeedbackAt:
          _parseNullableDate(map['latestParticipantFeedbackAt']),
      createdAt: _parseNullableDate(map['createdAt']),
      unreadMessagesCount: 0,
    );
  }

  void updateLastMessage(String message, DateTime date) {
    lastMessage = message;
    lastMessageDate = date;
  }

  bool get hasGuidedContext {
    return (contactReason?.trim().isNotEmpty ?? false) ||
        (contextType?.trim().isNotEmpty ?? false) ||
        (contextTitle?.trim().isNotEmpty ?? false);
  }

  bool get hasParticipantFeedback {
    return latestParticipantFeedbackStatus?.trim().isNotEmpty == true;
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

  static String? _normalizeNullableString(dynamic value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
