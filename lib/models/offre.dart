import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/models/user.dart';

class Offre {
  String id;
  String titre;
  String description;
  DateTime dateDebut;
  DateTime dateFin;
  AppUser recruteur;
  List<AppUser> candidats;
  String statut;
  DateTime dateCreation; // ✅ nouveau champ

  Offre({
    required this.id,
    required this.titre,
    required this.description,
    required this.dateDebut,
    required this.dateFin,
    required this.recruteur,
    required this.candidats,
    required this.statut,
    required this.dateCreation, // ✅
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titre': titre,
      'description': description,
      'dateDebut': dateDebut,
      'dateFin': dateFin,
      'recruteur': recruteur.toMap(),
      'candidats': candidats.map((joueur) => joueur.toMap()).toList(),
      'statut': statut,
      'dateCreation': dateCreation, // ✅
    };
  }

  factory Offre.fromMap(Map<String, dynamic> map) {
    return Offre(
      id: map['id'],
      titre: map['titre'],
      description: map['description'],
      dateDebut: (map['dateDebut'] as Timestamp).toDate(),
      dateFin: (map['dateFin'] as Timestamp).toDate(),
      recruteur: AppUser.fromMap(map['recruteur']),
      candidats: List<AppUser>.from(
          map['candidats']?.map((x) => AppUser.fromMap(x)) ?? []),
      statut: map['statut'],
      dateCreation: map['dateCreation'] != null
          ? (map['dateCreation'] as Timestamp).toDate()
          : DateTime.now(), // fallback sécurité
    );
  }
}

