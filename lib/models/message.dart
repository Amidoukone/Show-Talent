import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/models/user.dart';

class Message {
  final String id;
  final AppUser expediteur;
  final AppUser destinataire;
  final String contenu;
  final DateTime dateEnvoi;
  final bool estLu;

  Message({
    required this.id,
    required this.expediteur,
    required this.destinataire,
    required this.contenu,
    required this.dateEnvoi,
    required this.estLu,
  });

  // Convertir un message en Map (pour Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'expediteur': expediteur.toMap(),
      'destinataire': destinataire.toMap(),
      'contenu': contenu,
      'dateEnvoi': dateEnvoi,
      'estLu': estLu,
    };
  }

  // Créer un message à partir d'un Map (lire depuis Firestore)
  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      expediteur: AppUser.fromMap(map['expediteur']),
      destinataire: AppUser.fromMap(map['destinataire']),
      contenu: map['contenu'],
      dateEnvoi: (map['dateEnvoi'] as Timestamp).toDate(),
      estLu: map['estLu'],
    );
  }
}
