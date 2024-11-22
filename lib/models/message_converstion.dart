import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle représentant un message entre deux utilisateurs
class Message {
  final String id;
  final String expediteurId; // ID de l'expéditeur
  final String destinataireId; // ID du destinataire
  final String contenu; // Contenu du message
  final DateTime dateEnvoi; // Date d'envoi du message
  final bool estLu; // Indicateur si le message est lu

  Message({
    required this.id,
    required this.expediteurId,
    required this.destinataireId,
    required this.contenu,
    required this.dateEnvoi,
    required this.estLu,
  });

  /// Convertir un objet Message en Map pour Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'expediteurId': expediteurId,
      'destinataireId': destinataireId,
      'contenu': contenu,
      'dateEnvoi': Timestamp.fromDate(dateEnvoi),
      'estLu': estLu,
    };
  }

  /// Créer un objet Message à partir des données Firestore
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

/// Modèle représentant une conversation entre deux utilisateurs
class Conversation {
  final String id;
  final String utilisateur1Id; // ID du premier utilisateur
  final String utilisateur2Id; // ID du second utilisateur
  final List<String> utilisateurIds; // IDs des participants
  String? lastMessage; // Dernier message de la conversation
  DateTime? lastMessageDate; // Date du dernier message

  Conversation({
    required this.id,
    required this.utilisateur1Id,
    required this.utilisateur2Id,
    required this.utilisateurIds,
    this.lastMessage,
    this.lastMessageDate,
  });

  /// Convertir un objet Conversation en Map pour Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'utilisateur1Id': utilisateur1Id,
      'utilisateur2Id': utilisateur2Id,
      'utilisateurIds': utilisateurIds,
      'lastMessage': lastMessage,
      'lastMessageDate': lastMessageDate != null ? Timestamp.fromDate(lastMessageDate!) : null,
    };
  }

  /// Créer un objet Conversation à partir des données Firestore
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
    );
  }

  /// Met à jour le dernier message et sa date
  void updateLastMessage(String message, DateTime date) {
    lastMessage = message;
    lastMessageDate = date;
  }
}
