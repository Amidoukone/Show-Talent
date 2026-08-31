import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:adfoot/models/football_vocabulary.dart';

/// Ce qu'un recruteur lit d'un joueur, typé et interrogeable.
///
/// **Stocké à plat sur `users/{uid}`, groupé ici.** Les champs vivent au
/// premier niveau du document — `positionCodes`, `strongFoot`, `birthYear` —
/// parce qu'une requête Firestore n'indexe pas utilement un champ enfoui dans
/// une map, et que toute la valeur de ce modèle est d'être filtrable. Les
/// grouper dans cette classe est un confort de lecture côté code, pas une
/// forme de stockage.
///
/// Remplace `playerProfile`, qui portait du texte libre : postes en CSV,
/// qualités auto-déclarées, statistiques sans saison ni niveau. Les comptes de
/// production étant des comptes de test, il n'y a rien à migrer — voir
/// `docs/talent-search-spec.md`.
///
/// Deux champs sont absents de [toPatch] à dessein : `birthYear` et
/// `isSearchable` sont dérivés côté serveur. Le premier vient de `birthDate`,
/// qui vit dans le document privé et ne doit pas être exposé en entier ; le
/// second est un jugement sur la fiche, et une fiche ne décide pas seule
/// qu'elle mérite d'être montrée. Ils sont lus ici, jamais écrits.
class PlayerFootballProfile {
  const PlayerFootballProfile({
    this.birthYear,
    this.nationalities = const <String>[],
    this.positions = const <FootballPosition>[],
    this.strongFoot,
    this.heightCm,
    this.weightKg,
    this.contractStatus,
    this.contractEndDate,
    this.currentClubName,
    this.currentClubLevel,
    this.currentSeason,
    this.isSearchable = false,
  });

  /// Année de naissance seule, dérivée côté serveur.
  ///
  /// L'année suffit à filtrer une tranche d'âge — c'est ainsi qu'un club
  /// raisonne, « né en 2007 ou après » — et n'expose pas une date de
  /// naissance complète, qui reste dans `users/{uid}/private/contact`.
  final int? birthYear;

  /// Nationalités, en codes ISO 3166-1 alpha-2.
  ///
  /// Une liste, pas une valeur : le passeport décide de la voie d'obtention
  /// d'un permis de travail, et un joueur ivoirien avec un passeport français
  /// n'est pas la même proposition que le même joueur sans. C'est, après le
  /// poste, ce qui détermine le plus souvent si un club peut agir.
  ///
  /// À ne pas confondre avec `AppUser.country`, qui est une localisation.
  final List<String> nationalities;

  /// Postes déclarés, par ordre de préférence, au plus trois.
  final List<FootballPosition> positions;

  final StrongFoot? strongFoot;
  final int? heightCm;
  final int? weightKg;

  final ContractStatus? contractStatus;

  /// Fin de contrat, quand le statut en attend une.
  final DateTime? contractEndDate;

  final String? currentClubName;

  /// Niveau du club actuel.
  ///
  /// Sans lui une statistique ne veut rien dire : douze buts en académie U17
  /// et douze buts en première division ne se lisent pas de la même façon.
  final ClubLevel? currentClubLevel;

  /// La saison en cours. Une seule : un historique complet est un autre
  /// chantier, et une fiche qui en affiche cinq n'est plus lue.
  final SeasonRecord? currentSeason;

  /// Posé par le serveur : cette fiche mérite-t-elle d'apparaître dans une
  /// recherche de recruteur.
  final bool isSearchable;

  static const int minHeightCm = 120;
  static const int maxHeightCm = 230;
  static const int minWeightKg = 30;
  static const int maxWeightKg = 150;

  /// Le nombre maximum de nationalités retenues.
  ///
  /// Au-delà, la donnée n'est plus une information d'éligibilité mais une
  /// liste, et une liste ne se filtre plus utilement.
  static const int maxNationalities = 3;

  bool get isEmpty =>
      birthYear == null &&
      nationalities.isEmpty &&
      positions.isEmpty &&
      strongFoot == null &&
      heightCm == null &&
      weightKg == null &&
      contractStatus == null &&
      currentClubName == null &&
      currentClubLevel == null &&
      currentSeason == null;

  bool get isNotEmpty => !isEmpty;

  /// Le poste principal : le premier déclaré.
  FootballPosition? get primaryPosition =>
      positions.isEmpty ? null : positions.first;

  /// Lit les champs plats du document utilisateur.
  ///
  /// Tolérant par construction : une valeur illisible est absente, jamais une
  /// exception. Un document écrit par le portail admin ou par une version plus
  /// récente ne doit pas transformer un profil en écran blanc.
  factory PlayerFootballProfile.fromUserMap(Map<String, dynamic> map) {
    return PlayerFootballProfile(
      birthYear: _asInt(map['birthYear']),
      nationalities: _asCountryCodes(map['nationalities']),
      positions: FootballVocabulary.positions(map['positionCodes']),
      strongFoot: FootballVocabulary.strongFoot(map['strongFoot']),
      heightCm: _asBoundedInt(map['heightCm'], minHeightCm, maxHeightCm),
      weightKg: _asBoundedInt(map['weightKg'], minWeightKg, maxWeightKg),
      contractStatus: FootballVocabulary.contractStatus(map['contractStatus']),
      contractEndDate: _asDate(map['contractEndDate']),
      currentClubName: _asText(map['currentClubName']),
      currentClubLevel: FootballVocabulary.clubLevel(map['currentClubLevel']),
      currentSeason: SeasonRecord.fromMap(map['currentSeason']),
      isSearchable: map['isSearchable'] == true,
    );
  }

  /// Les champs que le titulaire du profil peut écrire.
  ///
  /// Les clés doivent correspondre exactement à la liste blanche
  /// `canUpdateOwnProfile` de firestore.rules — un champ absent de cette liste
  /// fait échouer tout l'enregistrement en `permission-denied`, pas seulement
  /// lui. Un test compare les deux.
  ///
  /// Ni `birthYear` ni `isSearchable` n'y figurent : ils sont dérivés côté
  /// serveur.
  Map<String, dynamic> toPatch() {
    return <String, dynamic>{
      'nationalities': nationalities,
      'positionCodes': positions.map((position) => position.code).toList(),
      'strongFoot': strongFoot?.code,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'contractStatus': contractStatus?.code,
      // Une date de fin n'a de sens que pour un contrat qui en a une : la
      // garder après un passage à « libre » laisserait un recruteur croire que
      // le joueur est encore engagé.
      'contractEndDate': contractStatus?.expectsEndDate == true
          ? (contractEndDate == null
                ? null
                : Timestamp.fromDate(contractEndDate!))
          : null,
      'currentClubName': currentClubName,
      'currentClubLevel': currentClubLevel?.code,
      'currentSeason': currentSeason?.toMap(),
    };
  }

  /// Les clés que [toPatch] produit, y compris les clés imbriquées de la
  /// saison. Sert au test qui les confronte à la liste blanche des règles.
  static List<String> get writableFieldPaths => <String>[
    'nationalities',
    'positionCodes',
    'strongFoot',
    'heightCm',
    'weightKg',
    'contractStatus',
    'contractEndDate',
    'currentClubName',
    'currentClubLevel',
    'currentSeason',
    ...SeasonRecord.writableFieldPaths,
  ];

  /// Les champs que seul le serveur écrit.
  static List<String> get serverDerivedFieldPaths => <String>[
    'birthYear',
    'isSearchable',
  ];

  PlayerFootballProfile copyWith({
    int? birthYear,
    List<String>? nationalities,
    List<FootballPosition>? positions,
    StrongFoot? strongFoot,
    int? heightCm,
    int? weightKg,
    ContractStatus? contractStatus,
    DateTime? contractEndDate,
    String? currentClubName,
    ClubLevel? currentClubLevel,
    SeasonRecord? currentSeason,
    bool? isSearchable,
  }) {
    return PlayerFootballProfile(
      birthYear: birthYear ?? this.birthYear,
      nationalities: nationalities ?? this.nationalities,
      positions: positions ?? this.positions,
      strongFoot: strongFoot ?? this.strongFoot,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      contractStatus: contractStatus ?? this.contractStatus,
      contractEndDate: contractEndDate ?? this.contractEndDate,
      currentClubName: currentClubName ?? this.currentClubName,
      currentClubLevel: currentClubLevel ?? this.currentClubLevel,
      currentSeason: currentSeason ?? this.currentSeason,
      isSearchable: isSearchable ?? this.isSearchable,
    );
  }
}

/// Une saison, avec ce qui lui donne un sens.
///
/// Les statistiques vivaient dans `playerProfile.stats` sans saison, sans
/// compétition et sans catégorie : « 900 minutes, 4 buts » ne dit rien tant
/// qu'on ignore en quelle année, dans quel championnat et dans quelle
/// catégorie d'âge. Un recruteur ne peut rien faire d'un chiffre nu.
class SeasonRecord {
  const SeasonRecord({
    this.season,
    this.competition,
    this.ageCategory,
    this.appearances,
    this.minutes,
    this.goals,
    this.assists,
  });

  /// Libellé de saison, tel que le football l'écrit : `2025-26`.
  final String? season;

  /// Championnat ou coupe.
  final String? competition;

  final AgeCategory? ageCategory;
  final int? appearances;
  final int? minutes;
  final int? goals;
  final int? assists;

  bool get isEmpty =>
      season == null &&
      competition == null &&
      ageCategory == null &&
      appearances == null &&
      minutes == null &&
      goals == null &&
      assists == null;

  static SeasonRecord? fromMap(Object? raw) {
    if (raw is! Map) return null;

    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final record = SeasonRecord(
      season: _asText(map['season']),
      competition: _asText(map['competition']),
      ageCategory: FootballVocabulary.ageCategory(map['ageCategory']),
      appearances: _asCount(map['appearances']),
      minutes: _asCount(map['minutes']),
      goals: _asCount(map['goals']),
      assists: _asCount(map['assists']),
    );

    return record.isEmpty ? null : record;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'season': season,
      'competition': competition,
      'ageCategory': ageCategory?.code,
      'appearances': appearances,
      'minutes': minutes,
      'goals': goals,
      'assists': assists,
    };
  }

  static List<String> get writableFieldPaths => <String>[
    'currentSeason.season',
    'currentSeason.competition',
    'currentSeason.ageCategory',
    'currentSeason.appearances',
    'currentSeason.minutes',
    'currentSeason.goals',
    'currentSeason.assists',
  ];
}

String? _asText(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

int? _asInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '');
}

/// Un compteur de match : jamais négatif, et absent plutôt que faux.
int? _asCount(Object? value) {
  final parsed = _asInt(value);
  if (parsed == null || parsed < 0) return null;
  return parsed;
}

int? _asBoundedInt(Object? value, int min, int max) {
  final parsed = _asInt(value);
  if (parsed == null || parsed < min || parsed > max) return null;
  return parsed;
}

DateTime? _asDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

/// Codes pays ISO 3166-1 alpha-2, en majuscules, sans doublon.
///
/// Rejette tout ce qui n'a pas exactement deux lettres : « Côte d'Ivoire »
/// écrit en toutes lettres est précisément ce que ce modèle remplace, et
/// l'accepter ici rouvrirait la porte au texte libre par le bas.
List<String> _asCountryCodes(Object? value) {
  if (value is! List) return const <String>[];

  final codes = <String>[];
  for (final entry in value) {
    final code = entry?.toString().trim().toUpperCase() ?? '';
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) continue;
    if (codes.contains(code)) continue;
    codes.add(code);
    if (codes.length == PlayerFootballProfile.maxNationalities) break;
  }
  return List<String>.unmodifiable(codes);
}
