import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/models/user.dart';

class Event {
  final String id;
  final String titre;
  final String description;
  final DateTime dateDebut;
  final DateTime dateFin;
  final AppUser organisateur;
  final List<AppUser> participants;
  String statut;
  final String lieu;
  final bool estPublic;
  final DateTime createdAt;

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
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titre': titre,
      'description': description,
      'dateDebut': Timestamp.fromDate(dateDebut),
      'dateFin': Timestamp.fromDate(dateFin),
      'organisateur': organisateur.toMap(),
      'participants': participants.map((p) => p.toMap()).toList(),
      'statut': statut,
      'lieu': lieu,
      'estPublic': estPublic,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Event.fromMap(Map<String, dynamic> map) {
    return Event(
      id: map['id'] ?? '',
      titre: map['titre'] ?? '',
      description: map['description'] ?? '',
      dateDebut: (map['dateDebut'] as Timestamp).toDate(),
      dateFin: (map['dateFin'] as Timestamp).toDate(),
      organisateur: AppUser.fromMap(map['organisateur'] ?? {}),
      participants: List<AppUser>.from(
        (map['participants'] ?? []).map((x) => AppUser.fromMap(x))),
      statut: map['statut'] ?? 'à venir',
      lieu: map['lieu'] ?? '',
      estPublic: map['estPublic'] ?? true,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

