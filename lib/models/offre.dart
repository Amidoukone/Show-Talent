import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/models/user.dart';

class Offre {
  final String id;
  final String titre;
  final String description;
  final DateTime dateDebut;
  final DateTime dateFin;
  final AppUser recruteur; // Utilisateur (recruteur ou club)
  final List<AppUser> candidats; // Liste des joueurs postulants
  String statut; // "ouverte", "fermée", "en cours"

  Offre({
    required this.id,
    required this.titre,
    required this.description,
    required this.dateDebut,
    required this.dateFin,
    required this.recruteur,
    required this.candidats,
    required this.statut,
  });

  // Méthode pour convertir une offre en Map (pour Firestore)
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
    };
  }

  // Méthode pour créer une offre à partir d'un Map (pour lire depuis Firestore)
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
    );
  }
}
