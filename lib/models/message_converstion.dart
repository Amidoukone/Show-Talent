import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle représentant un message entre deux utilisateurs
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
      id: map['id'] ?? '', // injecté par le controller depuis doc.id
      expediteurId: map['expediteurId'] ?? '',
      destinataireId: map['destinataireId'] ?? '',
      contenu: map['contenu'] ?? '',
      dateEnvoi: (map['dateEnvoi'] as Timestamp).toDate(),
      estLu: map['estLu'] ?? false,
    );
  }
}

/// Modèle représentant une conversation entre deux utilisateurs
class Conversation {
  final String id;
  final String utilisateur1Id;
  final String utilisateur2Id;
  final List<String> utilisateurIds;
  String? lastMessage;
  DateTime? lastMessageDate;
  int unreadMessagesCount;

  Conversation({
    required this.id,
    required this.utilisateur1Id,
    required this.utilisateur2Id,
    required this.utilisateurIds,
    this.lastMessage,
    this.lastMessageDate,
    this.unreadMessagesCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'utilisateur1Id': utilisateur1Id,
      'utilisateur2Id': utilisateur2Id,
      'utilisateurIds': utilisateurIds,
      'lastMessage': lastMessage,
      'lastMessageDate': lastMessageDate != null
          ? Timestamp.fromDate(lastMessageDate!)
          : null,
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] ?? '',
      utilisateur1Id: map['utilisateur1Id'] ?? '',
      utilisateur2Id: map['utilisateur2Id'] ?? '',
      utilisateurIds: List<String>.from(map['utilisateurIds'] ?? []),
      lastMessage: map['lastMessage'] ?? '',
      lastMessageDate: map['lastMessageDate'] != null
          ? (map['lastMessageDate'] as Timestamp).toDate()
          : null,
      unreadMessagesCount: 0, // ⚠️ Toujours initialisé ici
    );
  }

  void updateLastMessage(String message, DateTime date) {
    lastMessage = message;
    lastMessageDate = date;
  }
}
