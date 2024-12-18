import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/models/user.dart';

class NotificationModel {
  final String id;
  final AppUser destinataire; // Utilisateur recevant la notification
  final String message; // Contenu de la notification
  final String type; // Type de notification : "message", "offre", "événement", etc.
  final DateTime dateCreation; // Date de création
  bool estLue; // Indique si la notification est lue

  NotificationModel({
    required this.id,
    required this.destinataire,
    required this.message,
    required this.type,
    required this.dateCreation,
    this.estLue = false,
  });

  // Conversion en Map pour Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'destinataire': destinataire.toMap(), // AppUser converti en Map
      'message': message,
      'type': type,
      'dateCreation': Timestamp.fromDate(dateCreation), // Conversion en Timestamp
      'estLue': estLue,
    };
  }

  // Création à partir d'un Map provenant de Firestore
  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'] ?? '',
      destinataire: AppUser.fromMap(map['destinataire'] ?? {}),
      message: map['message'] ?? 'Message inconnu',
      type: map['type'] ?? 'général',
      dateCreation: (map['dateCreation'] as Timestamp?)?.toDate() ?? DateTime.now(),
      estLue: map['estLue'] ?? false,
    );
  }
}
