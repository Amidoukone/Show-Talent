import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/models/user.dart';

class Event {
  final String id;
  final String titre;
  final String description;
  final DateTime dateDebut;
  final DateTime dateFin;
  final AppUser organisateur; // Recruteur ou club organisateur de l'événement
  final List<AppUser> participants; // Liste des participants inscrits
  String statut; // "à venir", "en cours", "terminé"
  final String lieu;
  bool estPublic; // Événement public ou privé

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

  // Méthode pour convertir un événement en Map (pour Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titre': titre,
      'description': description,
      'dateDebut': dateDebut,
      'dateFin': dateFin,
      'organisateur': organisateur.toMap(),
      'participants': participants.map((participant) => participant.toMap()).toList(),
      'statut': statut,
      'lieu': lieu,
      'estPublic': estPublic,
    };
  }

  // Méthode pour créer un événement à partir d'un Map (pour lire depuis Firestore)
  factory Event.fromMap(Map<String, dynamic> map) {
    return Event(
      id: map['id'],
      titre: map['titre'],
      description: map['description'],
      dateDebut: (map['dateDebut'] as Timestamp).toDate(),
      dateFin: (map['dateFin'] as Timestamp).toDate(),
      organisateur: AppUser.fromMap(map['organisateur']),
      participants: List<AppUser>.from(
          map['participants']?.map((x) => AppUser.fromMap(x)) ?? []),
      statut: map['statut'],
      lieu: map['lieu'],
      estPublic: map['estPublic'] ?? true,
    );
  }
}
