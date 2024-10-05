import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String id;
  final String expediteurId;  // ID de l'expéditeur
  final String destinataireId;  // ID du destinataire
  final String contenu;  // Contenu du message
  final DateTime dateEnvoi;  // Date d'envoi du message
  final bool estLu;  // Indicateur si le message est lu

  Message({
    required this.id,
    required this.expediteurId,
    required this.destinataireId,
    required this.contenu,
    required this.dateEnvoi,
    required this.estLu,
  });

  // Convertir un objet Message en Map pour l'enregistrement dans Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'expediteurId': expediteurId,
      'destinataireId': destinataireId,
      'contenu': contenu,
      'dateEnvoi': Timestamp.fromDate(dateEnvoi),  // Convertir en Timestamp pour Firestore
      'estLu': estLu,
    };
  }

  // Créer un objet Message à partir des données Firestore
  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] ?? '',  // Gérer le cas où l'ID est null
      expediteurId: map['expediteurId'] ?? '',
      destinataireId: map['destinataireId'] ?? '',
      contenu: map['contenu'] ?? '',
      dateEnvoi: (map['dateEnvoi'] as Timestamp).toDate(),  // Convertir Timestamp en DateTime
      estLu: map['estLu'] ?? false,  // Par défaut, le message n'est pas lu
    );
  }
}

class Conversation {
  final String id;
  final String utilisateur1Id;  // ID du premier utilisateur
  final String utilisateur2Id;  // ID du second utilisateur
  final List<Message> messages;  // Liste des messages
  final String? lastMessage;  // Dernier message de la conversation (optionnel)
  final DateTime? lastMessageDate;  // Date du dernier message (optionnel)

  Conversation({
    required this.id,
    required this.utilisateur1Id,
    required this.utilisateur2Id,
    required this.messages,
    this.lastMessage,  // Dernier message (peut être null)
    this.lastMessageDate,  // Date du dernier message (peut être null)
  });

  // Convertir un objet Conversation en Map pour l'enregistrement dans Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'utilisateur1Id': utilisateur1Id,
      'utilisateur2Id': utilisateur2Id,
      'messages': messages.map((message) => message.toMap()).toList(),
      'lastMessage': lastMessage,
      'lastMessageDate': lastMessageDate != null ? Timestamp.fromDate(lastMessageDate!) : null,
    };
  }

  // Créer un objet Conversation à partir des données Firestore
  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] ?? '',
      utilisateur1Id: map['utilisateur1Id'] ?? '',
      utilisateur2Id: map['utilisateur2Id'] ?? '',
      messages: List<Message>.from(map['messages']?.map((x) => Message.fromMap(x)) ?? []),
      lastMessage: map['lastMessage'] ?? '',
      lastMessageDate: map['lastMessageDate'] != null
          ? (map['lastMessageDate'] as Timestamp).toDate()
          : null,
    );
  }
}
