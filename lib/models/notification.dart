import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/models/user.dart';

class NotificationModel {
  final String id;
  final AppUser destinataire; // Utilisateur recevant la notification
  final String message; // Contenu de la notification
  final String
      type; // Type de notification : "message", "offre", "événement", etc.
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
      'dateCreation':
          Timestamp.fromDate(dateCreation), // Conversion en Timestamp
      'estLue': estLue,
    };
  }

  // Création à partir d’un Map provenant de Firestore
  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    final rawDestinataire = map['destinataire'];
    return NotificationModel(
      id: map['id']?.toString() ?? '',
      destinataire: AppUser.fromMap(
        rawDestinataire is Map
            ? Map<String, dynamic>.from(rawDestinataire)
            : <String, dynamic>{},
      ),
      message: map['message']?.toString() ?? 'Message inconnu',
      type: map['type']?.toString() ?? 'général',
      dateCreation: _parseDate(map['dateCreation']),
      estLue: map['estLue'] == true,
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
