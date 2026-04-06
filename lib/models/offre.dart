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
  DateTime dateCreation;

  // Optional enriched fields
  String? localisation;
  String? remuneration;
  String? niveau;
  String? posteRecherche;
  String? pieceJointeUrl;
  int? vues;
  List<String>? viewedBy;
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
    required this.dateCreation,
    this.localisation,
    this.remuneration,
    this.niveau,
    this.posteRecherche,
    this.pieceJointeUrl,
    this.vues,
    this.viewedBy,
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
      'dateCreation': dateCreation,
      'localisation': localisation,
      'remuneration': remuneration,
      'niveau': niveau,
      'posteRecherche': posteRecherche,
      'pieceJointeUrl': pieceJointeUrl,
      'vues': vues,
      'viewedBy': viewedBy,
      'archivedAt': archivedAt,
      'lastUpdated': lastUpdated,
    };
  }

  static DateTime _parseDate(
    dynamic value, {
    DateTime? fallback,
  }) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback ?? DateTime.now();
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  factory Offre.fromMap(
    Map<String, dynamic> map, {
    String? fallbackId,
  }) {
    final rawId = map['id']?.toString().trim() ?? '';
    final resolvedId = rawId.isNotEmpty ? rawId : (fallbackId ?? '');
    final rawRecruteur = map['recruteur'];
    final recruteurMap = rawRecruteur is Map
        ? Map<String, dynamic>.from(rawRecruteur)
        : <String, dynamic>{};
    final rawCandidats = map['candidats'];
    final candidatMaps = rawCandidats is List
        ? rawCandidats
            .whereType<Map>()
            .map((candidate) => Map<String, dynamic>.from(candidate))
            .toList()
        : const <Map<String, dynamic>>[];

    return Offre(
      id: resolvedId,
      titre: map['titre']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      dateDebut: _parseDate(map['dateDebut']),
      dateFin: _parseDate(map['dateFin']),
      recruteur: AppUser.fromMap(recruteurMap),
      candidats: List<AppUser>.from(candidatMaps.map(AppUser.fromMap)),
      statut: map['statut']?.toString() ?? 'ouverte',
      dateCreation: _parseDate(map['dateCreation']),
      localisation: map['localisation'] as String?,
      remuneration: map['remuneration'] as String?,
      niveau: map['niveau'] as String?,
      posteRecherche: map['posteRecherche'] as String?,
      pieceJointeUrl: map['pieceJointeUrl'] as String?,
      vues: (map['vues'] as num?)?.toInt(),
      viewedBy: map['viewedBy'] is List
          ? (map['viewedBy'] as List).map((id) => id.toString()).toList()
          : null,
      archivedAt: _parseNullableDate(map['archivedAt']),
      lastUpdated: _parseNullableDate(map['lastUpdated']),
    );
  }

  factory Offre.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Offre.fromMap(data, fallbackId: doc.id);
  }
}
