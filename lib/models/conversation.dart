

import 'package:show_talent/models/message.dart';
import 'package:show_talent/models/user.dart';

class Conversation {
  final String id;
  final AppUser utilisateur1;
  final AppUser utilisateur2;
  final List<Message> messages;

  Conversation({
    required this.id,
    required this.utilisateur1,
    required this.utilisateur2,
    required this.messages,
  });

  // Convertir une conversation en Map (pour Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'utilisateur1': utilisateur1.toMap(),
      'utilisateur2': utilisateur2.toMap(),
      'messages': messages.map((message) => message.toMap()).toList(),
    };
  }

  // Créer une conversation à partir d'un Map (lire depuis Firestore)
  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'],
      utilisateur1: AppUser.fromMap(map['utilisateur1']),
      utilisateur2: AppUser.fromMap(map['utilisateur2']),
      messages: List<Message>.from(
          map['messages']?.map((x) => Message.fromMap(x)) ?? []),
    );
  }
}
