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

  /// Statuts recommandés : brouillon / ouvert / fermé / archivé
  String statut;

  final String lieu;
  final bool estPublic;
  final DateTime createdAt;

  // Champs optionnels additionnels (rétrocompatibles)
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

  /// 🔢 Nombre total de participants
  int get nbParticipants => participants.length;

  /// 📅 Vérifie si la date de fin est dépassée
  bool get isExpired => dateFin.isBefore(DateTime.now());

  /// 🔒 Indique si l'événement est "inscriptible"
  bool get isOpenForRegistration =>
      statut == 'ouvert' && (archivedAt == null);

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

      // Champs optionnels (écriture conditionnelle pour garder Firestore propre)
      if (capaciteMax != null) 'capaciteMax': capaciteMax,
      if (tags != null) 'tags': tags,
      if (streamingUrl != null) 'streamingUrl': streamingUrl,
      if (flyerUrl != null) 'flyerUrl': flyerUrl,
      if (views != null) 'views': views,
      if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt!),
      if (lastUpdated != null) 'lastUpdated': Timestamp.fromDate(lastUpdated!),
    };
  }

  factory Event.fromMap(Map<String, dynamic> map) {
    // Participants : robuste même si null / mal formé
    final rawParticipants = map['participants'];
    final List<AppUser> parsedParticipants = rawParticipants is List
        ? rawParticipants
            .map((x) => AppUser.fromMap((x as Map?)?.cast<String, dynamic>() ?? {}))
            .toList()
        : <AppUser>[];

    return Event(
      id: map['id'] ?? '',
      titre: map['titre'] ?? '',
      description: map['description'] ?? '',
      dateDebut: (map['dateDebut'] as Timestamp).toDate(),
      dateFin: (map['dateFin'] as Timestamp).toDate(),
      organisateur: AppUser.fromMap(
        (map['organisateur'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      participants: parsedParticipants,

      // Par défaut : "ouvert" (aligné avec le controller)
      statut: map['statut'] ?? 'ouvert',

      lieu: map['lieu'] ?? '',
      estPublic: map['estPublic'] ?? true,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),

      capaciteMax: (map['capaciteMax'] as num?)?.toInt(),
      tags: map['tags'] is List ? List<String>.from(map['tags'] as List) : null,
      streamingUrl: map['streamingUrl'] as String?,
      flyerUrl: map['flyerUrl'] as String?,
      views: (map['views'] as num?)?.toInt(),
      archivedAt: (map['archivedAt'] as Timestamp?)?.toDate(),
      lastUpdated: (map['lastUpdated'] as Timestamp?)?.toDate(),
    );
  }
}
