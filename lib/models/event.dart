import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/models/user.dart';

class Event {
  final String id;
  final String titre;
  final String description;
  final DateTime dateDebut;
  final DateTime dateFin;
  final AppUser organisateur; // Propriétaire de l'événement
  final List<AppUser> participants; // Liste des participants inscrits
  String statut; // "à venir", "en cours", "terminé"
  final String lieu;
  final bool estPublic; // Événement public ou privé

  Event({
    required this.id,
    required this.titre,
    required this.description,
    required this.dateDebut,
    required this.dateFin,
    required this.organisateur,
    required this.participants,
    required this.statut,
    required this.lieu,
    required this.estPublic,
  });

  // Convertir un événement en Map (pour Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titre': titre,
      'description': description,
      'dateDebut': Timestamp.fromDate(dateDebut),
      'dateFin': Timestamp.fromDate(dateFin),
      'organisateur': organisateur.toMap(),
      'participants':
          participants.map((participant) => participant.toMap()).toList(),
      'statut': statut,
      'lieu': lieu,
      'estPublic': estPublic,
    };
  }

  // Créer un événement à partir d'un Map (pour lire depuis Firestore)
  factory Event.fromMap(Map<String, dynamic> map) {
    return Event(
      id: map['id'] ?? '',
      titre: map['titre'] ?? 'Titre non spécifié',
      description: map['description'] ?? '',
      dateDebut: (map['dateDebut'] as Timestamp).toDate(),
      dateFin: (map['dateFin'] as Timestamp).toDate(),
      organisateur: AppUser.fromMap(map['organisateur'] ?? {}),
      participants: List<AppUser>.from(
          (map['participants'] ?? []).map((x) => AppUser.fromMap(x))),
      statut: map['statut'] ?? 'à venir',
      lieu: map['lieu'] ?? 'Lieu non spécifié',
      estPublic: map['estPublic'] ?? true,
    );
  }
}
