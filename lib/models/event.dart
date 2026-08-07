import 'package:adfoot/models/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Event {
  final String id;
  final String titre;
  final String description;
  final DateTime dateDebut;
  final DateTime dateFin;
  final AppUser organisateur;
  final List<AppUser> participants;

  // Canonical statuses: brouillon / ouvert / ferme / archive.
  String statut;

  final String lieu;
  final bool estPublic;
  final DateTime createdAt;

  // Optional fields.
  int? capaciteMax;
  List<String>? tags;
  String? streamingUrl;
  String? flyerUrl;
  int? views;
  DateTime? archivedAt;
  DateTime? lastUpdated;

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
    this.capaciteMax,
    this.tags,
    this.streamingUrl,
    this.flyerUrl,
    this.views,
    this.archivedAt,
    this.lastUpdated,
  });

  static String normalizeStatus(String rawStatus) {
    final value = rawStatus.trim().toLowerCase();
    switch (value) {
      case 'ouvert':
      case 'open':
        return 'ouvert';
      case 'ferme':
      case 'ferm\u00e9':
      case 'ferm\u00c3\u00a9':
      case 'ferm\u00c3\u00a3\u00c2\u00a9':
      case 'closed':
        return 'ferme';
      case 'archive':
      case 'archiv\u00e9':
      case 'archiv\u00c3\u00a9':
      case 'archiv\u00c3\u00a3\u00c2\u00a9':
      case 'archived':
        return 'archive';
      case 'brouillon':
      case 'draft':
        return 'brouillon';
      default:
        return value;
    }
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

  int get nbParticipants => participants.length;

  bool get isExpired => dateFin.isBefore(DateTime.now());

  bool get isOpenForRegistration =>
      normalizeStatus(statut) == 'ouvert' && archivedAt == null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titre': titre,
      'description': description,
      'dateDebut': Timestamp.fromDate(dateDebut),
      'dateFin': Timestamp.fromDate(dateFin),
      'organisateur': organisateur.toEmbeddedMap(),
      'participants': participants.map((p) => p.toEmbeddedMap()).toList(),
      'statut': normalizeStatus(statut),
      'lieu': lieu,
      'estPublic': estPublic,
      'createdAt': Timestamp.fromDate(createdAt),
      if (capaciteMax != null) 'capaciteMax': capaciteMax,
      if (tags != null) 'tags': tags,
      if (streamingUrl != null) 'streamingUrl': streamingUrl,
      if (flyerUrl != null) 'flyerUrl': flyerUrl,
      if (views != null) 'views': views,
      if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt!),
      if (lastUpdated != null) 'lastUpdated': Timestamp.fromDate(lastUpdated!),
    };
  }

  factory Event.fromMap(
    Map<String, dynamic> map, {
    String? fallbackId,
  }) {
    final rawParticipants =
        _readFirst(map, ['participants', 'inscrits', 'candidats']);
    final participantMaps = rawParticipants is List
        ? rawParticipants
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList()
        : const <Map<String, dynamic>>[];

    final rawOrganisateur =
        _readFirst(map, ['organisateur', 'owner', 'author', 'recruteur']);
    final organisateurMap = rawOrganisateur is Map
        ? Map<String, dynamic>.from(rawOrganisateur)
        : <String, dynamic>{
            'uid': _readFirst(
              map,
              ['organisateurUid', 'ownerUid', 'authorUid', 'recruteurUid'],
            ),
            'nom': _readFirst(
              map,
              ['organisateurNom', 'ownerName', 'authorName', 'recruteurNom'],
            ),
            'email': _readFirst(
              map,
              ['organisateurEmail', 'ownerEmail', 'authorEmail'],
            ),
            'role': _readFirst(
              map,
              [
                'organisateurRole',
                'ownerRole',
                'authorRole',
                'recruteurRole',
                'role',
              ],
            ),
            'photoProfil': _readFirst(
              map,
              [
                'organisateurPhoto',
                'ownerPhoto',
                'authorPhoto',
                'recruteurPhoto',
                'photoProfil',
              ],
            ),
          };

    final rawId = map['id']?.toString().trim() ?? '';
    final resolvedId = rawId.isNotEmpty ? rawId : (fallbackId ?? '');

    return Event(
      id: resolvedId,
      titre: _readFirst(map, ['titre', 'title', 'nom'])?.toString() ?? '',
      description:
          _readFirst(map, ['description', 'details', 'contenu', 'body'])
                  ?.toString() ??
              '',
      dateDebut: _parseDate(
        _readFirst(map, ['dateDebut', 'startDate', 'date']),
      ),
      dateFin: _parseDate(
        _readFirst(map, ['dateFin', 'endDate', 'expirationDate']),
      ),
      organisateur: AppUser.fromEmbeddedMap(organisateurMap),
      participants: participantMaps.map(AppUser.fromEmbeddedMap).toList(),
      statut: normalizeStatus(
        _readFirst(map, ['statut', 'status'])?.toString() ?? 'ouvert',
      ),
      lieu: _readFirst(map, ['lieu', 'location', 'localisation'])?.toString() ??
          '',
      estPublic:
          (_readFirst(map, ['estPublic', 'isPublic', 'public']) as bool?) ??
              true,
      createdAt: _parseDate(
        _readFirst(map, ['createdAt', 'dateCreation', 'publishedAt']),
      ),
      capaciteMax:
          (_readFirst(map, ['capaciteMax', 'capacity', 'maxParticipants'])
                  as num?)
              ?.toInt(),
      tags: map['tags'] is List
          ? (map['tags'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
          : null,
      streamingUrl: map['streamingUrl'] as String?,
      flyerUrl: map['flyerUrl'] as String?,
      views: (map['views'] as num?)?.toInt(),
      archivedAt: _parseNullableDate(map['archivedAt']),
      lastUpdated: _parseNullableDate(map['lastUpdated']),
    );
  }

  factory Event.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Event.fromMap(data, fallbackId: doc.id);
  }
}
