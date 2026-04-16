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
      'recruteur': recruteur.toEmbeddedMap(),
      'candidats': candidats.map((joueur) => joueur.toEmbeddedMap()).toList(),
      'statut': normalizeStatus(statut),
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

  static dynamic _readFirst(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key];
      }
    }
    return null;
  }

  static String normalizeStatus(String rawStatus) {
    final value = rawStatus.trim().toLowerCase();
    switch (value) {
      case 'ouverte':
      case 'open':
        return 'ouverte';
      case 'fermee':
      case 'fermée':
      case 'closed':
        return 'fermee';
      case 'archivee':
      case 'archivée':
      case 'archive':
      case 'archived':
        return 'archivee';
      case 'brouillon':
      case 'draft':
        return 'brouillon';
      default:
        return value;
    }
  }

  factory Offre.fromMap(
    Map<String, dynamic> map, {
    String? fallbackId,
  }) {
    final rawId = map['id']?.toString().trim() ?? '';
    final resolvedId = rawId.isNotEmpty ? rawId : (fallbackId ?? '');
    final rawRecruteur =
        _readFirst(map, ['recruteur', 'owner', 'author', 'club']);
    final recruteurMap = rawRecruteur is Map
        ? Map<String, dynamic>.from(rawRecruteur)
        : <String, dynamic>{
            'uid': _readFirst(
              map,
              ['recruteurUid', 'ownerUid', 'authorUid', 'clubUid', 'userId'],
            ),
            'nom': _readFirst(
              map,
              ['recruteurNom', 'ownerName', 'authorName', 'clubNom'],
            ),
            'email': _readFirst(
              map,
              ['recruteurEmail', 'ownerEmail', 'authorEmail'],
            ),
            'role': _readFirst(
              map,
              ['recruteurRole', 'ownerRole', 'authorRole', 'clubRole', 'role'],
            ),
            'photoProfil': _readFirst(
              map,
              ['recruteurPhoto', 'ownerPhoto', 'authorPhoto', 'photoProfil'],
            ),
          };
    final rawCandidats =
        _readFirst(map, ['candidats', 'participants', 'applications']);
    final candidatMaps = rawCandidats is List
        ? rawCandidats
            .whereType<Map>()
            .map((candidate) => Map<String, dynamic>.from(candidate))
            .toList()
        : const <Map<String, dynamic>>[];

    return Offre(
      id: resolvedId,
      titre: _readFirst(map, ['titre', 'title', 'intitule', 'poste'])
              ?.toString() ??
          '',
      description:
          _readFirst(map, ['description', 'details', 'contenu', 'body'])
                  ?.toString() ??
              '',
      dateDebut: _parseDate(
        _readFirst(
            map, ['dateDebut', 'startDate', 'createdAt', 'dateCreation']),
      ),
      dateFin: _parseDate(
        _readFirst(map, ['dateFin', 'endDate', 'expirationDate', 'expiresAt']),
      ),
      recruteur: AppUser.fromEmbeddedMap(recruteurMap),
      candidats: List<AppUser>.from(candidatMaps.map(AppUser.fromEmbeddedMap)),
      statut: normalizeStatus(
        _readFirst(map, ['statut', 'status'])?.toString() ?? 'ouverte',
      ),
      dateCreation: _parseDate(
        _readFirst(map, ['dateCreation', 'createdAt', 'publishedAt']),
      ),
      localisation:
          _readFirst(map, ['localisation', 'location', 'lieu'])?.toString(),
      remuneration:
          _readFirst(map, ['remuneration', 'salary', 'salaire'])?.toString(),
      niveau: _readFirst(map, ['niveau', 'level'])?.toString(),
      posteRecherche:
          _readFirst(map, ['posteRecherche', 'poste', 'position'])?.toString(),
      pieceJointeUrl: _readFirst(
        map,
        ['pieceJointeUrl', 'attachmentUrl', 'documentUrl'],
      )?.toString(),
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
