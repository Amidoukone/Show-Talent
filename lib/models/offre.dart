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

  // Champs enrichis (facultatifs)
  String? localisation;
  String? remuneration;
  String? niveau;
  String? posteRecherche;
  String? pieceJointeUrl;
  int? vues;
  DateTime? archivedAt;
  DateTime? lastUpdated;

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
    this.localisation,
    this.remuneration,
    this.niveau,
    this.posteRecherche,
    this.pieceJointeUrl,
    this.vues,
    this.archivedAt,
    this.lastUpdated,
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

      // champs enrichis
      'localisation': localisation,
      'remuneration': remuneration,
      'niveau': niveau,
      'posteRecherche': posteRecherche,
      'pieceJointeUrl': pieceJointeUrl,
      'vues': vues,
      'archivedAt': archivedAt,
      'lastUpdated': lastUpdated,
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
        map['candidats']?.map((x) => AppUser.fromMap(x)) ?? [],
      ),
      statut: map['statut'] ?? 'ouverte',
      dateCreation: map['dateCreation'] != null
          ? (map['dateCreation'] as Timestamp).toDate()
          : DateTime.now(), // fallback sécurité

      // champs enrichis
      localisation: map['localisation'] as String?,
      remuneration: map['remuneration'] as String?,
      niveau: map['niveau'] as String?,
      posteRecherche: map['posteRecherche'] as String?,
      pieceJointeUrl: map['pieceJointeUrl'] as String?,
      vues: (map['vues'] as num?)?.toInt(),
      archivedAt: (map['archivedAt'] as Timestamp?)?.toDate(),
      lastUpdated: (map['lastUpdated'] as Timestamp?)?.toDate(),
    );
  }
}
