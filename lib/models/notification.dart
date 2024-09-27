
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/models/user.dart'; 

class NotificationModel {
  final String id;
  final AppUser destinataire; // Utilisateur qui reçoit la notification
  final String message; // Contenu de la notification
  final String type; // Type de la notification : "message", "offre", "événement", etc.
  final DateTime dateCreation; // Date de création de la notification
  bool estLue; // Indique si la notification a été lue ou non

  NotificationModel({
    required this.id,
    required this.destinataire,
    required this.message,
    required this.type,
    required this.dateCreation,
    this.estLue = false, // Par défaut non lue
  });

  // Convertir la notification en Map (pour Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'destinataire': destinataire.toMap(),
      'message': message,
      'type': type,
      'dateCreation': dateCreation,
      'estLue': estLue,
    };
  }

  // Créer une notification à partir d'un Map (depuis Firestore)
  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'],
      destinataire: AppUser.fromMap(map['destinataire']),
      message: map['message'],
      type: map['type'],
      // Correction ici, utilisez Timestamp pour convertir en DateTime
      dateCreation: (map['dateCreation'] as Timestamp).toDate(),
      estLue: map['estLue'] ?? false,
    );
  }
}
