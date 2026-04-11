import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/offre.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/account_role_policy.dart';

class AppUser {
  // =========================
  // 🔑 Identité & système
  // =========================
  String uid;
  String nom;
  String email;
  String role;
  String photoProfil;
  bool estActif;
  bool estBloque;
  bool authDisabled;
  bool emailVerified;
  bool createdByAdmin;
  int followers;
  int followings;
  DateTime dateInscription;
  DateTime dernierLogin;
  DateTime? emailVerifiedAt;
  String? phone;
  String? blockedReason;
  DateTime? blockedUntil;
  String? blockMode;
  String? authDisabledReason;

  // =========================
  // 🌍 Champs transverses
  // =========================
  DateTime? birthDate; // âge calculé côté client
  String? country;
  String? city;
  String? region;
  List<String>? languages; // ex: ['fr', 'en']
  bool? openToOpportunities;

  // =========================
  // 🧍 Profil joueur (MVP existant)
  // =========================
  String? bio;
  String? position;
  String? clubActuel;
  int? nombreDeMatchs;
  int? buts;
  int? assistances;
  List<Video>? videosPubliees;
  Map<String, double>? performances;

  // =========================
  // 🧠 Profil joueur (avancé – structuré)
  // =========================
  Map<String, dynamic>? playerProfile;
  /*
    playerProfile: {
      physical: {
        heightCm,
        weightKg,
        strongFoot
      },
      positions: [],
      skills: [],
      stats: {
        minutes,
        goals,
        assists
      },
      availability: {
        open,
        regions
      }
    }
  */

  // =========================
  // 🏟️ Club / Staff
  // =========================
  String? nomClub;
  String? ligue;
  List<Offre>? offrePubliees;
  List<Event>? eventPublies;
  Map<String, dynamic>? clubProfile;
  /*
    clubProfile: {
      structureType: 'pro' | 'academy' | 'semi-pro',
      categories: ['U17', 'U19', 'Seniors'],
      needs: [
        { position: 'CB', priority: 'high' }
      ]
    }
  */

  // =========================
  // 🧑‍💼 Recruteur / Agent
  // =========================
  String? entreprise;
  int? nombreDeRecrutements;
  Map<String, dynamic>? agentProfile;
  /*
    agentProfile: {
      licenseNumber: 'FIFA-XXXX',
      licenseCountry: 'FR',
      zones: ['Europe', 'Afrique']
    }
  */

  // =========================
  // 🎪 Organisateur d’événements
  // =========================
  Map<String, dynamic>? eventOrganizerProfile;

  // =========================
  // 🔗 Social & contenus
  // =========================
  String? team;
  List<AppUser>? joueursSuivis;
  List<AppUser>? clubsSuivis;
  List<Video>? videosLikees;
  List<String> followersList;
  List<String> followingsList;
  bool profilePublic;
  bool allowMessages;

  // =========================
  // 📄 Documents
  // =========================
  String? cvUrl;

  AppUser({
    required this.uid,
    required this.nom,
    required this.email,
    required this.role,
    required this.photoProfil,
    required this.estActif,
    required this.estBloque,
    this.authDisabled = false,
    required this.emailVerified,
    this.createdByAdmin = false,
    required this.followers,
    required this.followings,
    required this.dateInscription,
    required this.dernierLogin,
    this.emailVerifiedAt,
    this.phone,
    this.blockedReason,
    this.blockedUntil,
    this.blockMode,
    this.authDisabledReason,

    // Transverses
    this.birthDate,
    this.country,
    this.city,
    this.region,
    this.languages,
    this.openToOpportunities,

    // Joueur MVP
    this.bio,
    this.position,
    this.clubActuel,
    this.nombreDeMatchs,
    this.buts,
    this.assistances,
    this.videosPubliees,
    this.performances,

    // Avancés par rôle
    this.playerProfile,
    this.clubProfile,
    this.agentProfile,
    this.eventOrganizerProfile,

    // Club / recruteur
    this.nomClub,
    this.ligue,
    this.offrePubliees,
    this.eventPublies,
    this.entreprise,
    this.nombreDeRecrutements,

    // Social
    this.team,
    this.joueursSuivis,
    this.clubsSuivis,
    this.videosLikees,
    required this.followersList,
    required this.followingsList,

    // Docs
    this.cvUrl,
    this.profilePublic = true,
    this.allowMessages = true,
  });

  // =========================
  // 🔁 Parsing Firestore SAFE
  // =========================
  factory AppUser.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? safeMap(dynamic v) {
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    List<T>? safeList<T>(dynamic v) {
      if (v is List) return v.cast<T>();
      return null;
    }

    return AppUser(
      uid: map['uid'] ?? '',
      nom: map['nom'] ?? 'Nom inconnu',
      email: map['email'] ?? '',
      role: map['role'] ?? 'utilisateur',
      photoProfil: map['photoProfil'] ?? '',
      estActif: map['estActif'] ?? false,
      estBloque: map['estBloque'] ?? false,
      authDisabled: map['authDisabled'] == true,
      emailVerified: map['emailVerified'] ?? false,
      createdByAdmin: map['createdByAdmin'] as bool? ?? false,
      emailVerifiedAt: (map['emailVerifiedAt'] as Timestamp?)?.toDate(),
      followers: (map['followers'] as num?)?.toInt() ?? 0,
      followings: (map['followings'] as num?)?.toInt() ?? 0,
      dateInscription:
          (map['dateInscription'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dernierLogin:
          (map['dernierLogin'] as Timestamp?)?.toDate() ?? DateTime.now(),
      phone: map['phone']?.toString(),
      blockedReason: map['blockedReason']?.toString(),
      blockedUntil: _parseNullableDate(map['blockedUntil']),
      blockMode: _normalizeBlockMode(map['blockMode']?.toString()),
      authDisabledReason: map['authDisabledReason']?.toString(),

      // Transverses
      birthDate: (map['birthDate'] as Timestamp?)?.toDate(),
      country: map['country']?.toString(),
      city: map['city']?.toString(),
      region: map['region']?.toString(),
      languages: map['languages'] != null
          ? List<String>.from(
              (map['languages'] as List).map((e) => e.toString()))
          : null,
      openToOpportunities: map['openToOpportunities'] as bool?,

      // Joueur MVP
      bio: map['bio']?.toString(),
      position: map['position']?.toString(),
      clubActuel: map['clubActuel']?.toString(),
      nombreDeMatchs: (map['nombreDeMatchs'] as num?)?.toInt(),
      buts: (map['buts'] as num?)?.toInt(),
      assistances: (map['assistances'] as num?)?.toInt(),

      videosPubliees: map['videosPubliees'] is List
          ? (map['videosPubliees'] as List)
              .map((v) => Video.fromMap(Map<String, dynamic>.from(v as Map)))
              .toList()
          : null,

      performances: map['performances'] is Map
          ? Map<String, double>.from(
              (map['performances'] as Map).map(
                (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
              ),
            )
          : null,

      // Avancés
      playerProfile: safeMap(map['playerProfile']),
      clubProfile: safeMap(map['clubProfile']),
      agentProfile: safeMap(map['agentProfile']),
      eventOrganizerProfile: safeMap(map['eventOrganizerProfile']),

      // Club / recruteur
      nomClub: map['nomClub']?.toString(),
      ligue: map['ligue']?.toString(),

      offrePubliees: map['offrePubliees'] is List
          ? (map['offrePubliees'] as List)
              .map((v) => Offre.fromMap(Map<String, dynamic>.from(v as Map)))
              .toList()
          : null,

      eventPublies: map['eventPublies'] is List
          ? (map['eventPublies'] as List)
              .map((v) => Event.fromMap(Map<String, dynamic>.from(v as Map)))
              .toList()
          : null,

      entreprise: map['entreprise']?.toString(),
      nombreDeRecrutements: (map['nombreDeRecrutements'] as num?)?.toInt(),

      // Social
      team: map['team']?.toString(),

      joueursSuivis: map['joueursSuivis'] is List
          ? (map['joueursSuivis'] as List)
              .map((j) => AppUser.fromMap(Map<String, dynamic>.from(j as Map)))
              .toList()
          : null,

      clubsSuivis: map['clubsSuivis'] is List
          ? (map['clubsSuivis'] as List)
              .map((c) => AppUser.fromMap(Map<String, dynamic>.from(c as Map)))
              .toList()
          : null,

      videosLikees: map['videosLikees'] is List
          ? (map['videosLikees'] as List)
              .map((v) => Video.fromMap(Map<String, dynamic>.from(v as Map)))
              .toList()
          : null,

      followersList: (safeList<dynamic>(map['followersList']) ?? [])
          .map((e) => e.toString())
          .toList(),

      followingsList: (safeList<dynamic>(map['followingsList']) ?? [])
          .map((e) => e.toString())
          .toList(),

      // Docs
      cvUrl: map['cvUrl']?.toString(),
      profilePublic: map['profilePublic'] as bool? ?? true,
      allowMessages: map['allowMessages'] as bool? ?? true,
    );
  }

  // =========================
  // ⬆️ Firestore export SAFE
  // =========================
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'nom': nom,
      'email': email,
      'role': role,
      'photoProfil': photoProfil,
      'estActif': estActif,
      'estBloque': estBloque,
      'authDisabled': authDisabled,
      'emailVerified': emailVerified,
      'createdByAdmin': createdByAdmin,
      'emailVerifiedAt':
          emailVerifiedAt != null ? Timestamp.fromDate(emailVerifiedAt!) : null,
      'followers': followers,
      'followings': followings,
      'dateInscription': Timestamp.fromDate(dateInscription),
      'dernierLogin': Timestamp.fromDate(dernierLogin),
      'phone': phone,
      'blockedReason': blockedReason,
      'blockedUntil':
          blockedUntil != null ? Timestamp.fromDate(blockedUntil!) : null,
      'blockMode': blockMode,
      'authDisabledReason': authDisabledReason,

      // Transverses
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
      'country': country,
      'city': city,
      'region': region,
      'languages': languages,
      'openToOpportunities': openToOpportunities,

      // Joueur MVP
      'bio': bio,
      'position': position,
      'clubActuel': clubActuel,
      'nombreDeMatchs': nombreDeMatchs,
      'buts': buts,
      'assistances': assistances,
      'videosPubliees': videosPubliees?.map((v) => v.toMap()).toList(),
      'performances': performances,

      // Avancés
      'playerProfile': playerProfile,
      'clubProfile': clubProfile,
      'agentProfile': agentProfile,
      'eventOrganizerProfile': eventOrganizerProfile,

      // Club / recruteur
      'nomClub': nomClub,
      'ligue': ligue,
      'offrePubliees': offrePubliees?.map((o) => o.toMap()).toList(),
      'eventPublies': eventPublies?.map((e) => e.toMap()).toList(),
      'entreprise': entreprise,
      'nombreDeRecrutements': nombreDeRecrutements,

      // Social
      'team': team,
      'joueursSuivis': joueursSuivis?.map((j) => j.toMap()).toList(),
      'clubsSuivis': clubsSuivis?.map((c) => c.toMap()).toList(),
      'videosLikees': videosLikees?.map((v) => v.toMap()).toList(),
      'followersList': followersList,
      'followingsList': followingsList,

      // Docs
      'cvUrl': cvUrl,
      'profilePublic': profilePublic,
      'allowMessages': allowMessages,
    };
  }

  // =========================
  // 🎂 Âge calculé (safe)
  // =========================
  int? get age {
    if (birthDate == null) return null;
    final now = DateTime.now();
    int age = now.year - birthDate!.year;
    if (now.month < birthDate!.month ||
        (now.month == birthDate!.month && now.day < birthDate!.day)) {
      age--;
    }
    return age;
  }

  // =========================
  // UI GETTERS (MVP / AVANCE)
  // =========================

  /// Rôle helpers
  bool get isPlayer => role == 'joueur';
  bool get isClub => role == 'club';
  bool get isAgent => role == 'agent';
  bool get isRecruiter => role == 'recruteur' || role == 'agent';
  bool get isCoach => role == 'coach';
  bool get isFan => role == 'fan';
  bool get canPublishOpportunities => isOpportunityPublisherRole(role);
  bool get hasTemporaryBlock => estBloque && blockMode == 'temporary';
  bool get hasPermanentBlock => estBloque && !hasTemporaryBlock;

  bool get hasActiveAppBlock {
    if (!estBloque) {
      return false;
    }

    if (!hasTemporaryBlock) {
      return true;
    }

    final endsAt = blockedUntil;
    if (endsAt == null) {
      return true;
    }

    return endsAt.isAfter(DateTime.now());
  }

  bool get hasExpiredTemporaryBlock {
    if (!hasTemporaryBlock) {
      return false;
    }

    final endsAt = blockedUntil;
    if (endsAt == null) {
      return false;
    }

    return !endsAt.isAfter(DateTime.now());
  }

  bool get isEffectivelyActiveAccount => !authDisabled && emailVerified;

  bool get canAppearInMessagingDirectory {
    return uid.trim().isNotEmpty &&
        nom.trim().isNotEmpty &&
        !authDisabled &&
        !isAdminPortalOnlyRole(role);
  }

  /// -------------------------
  /// MVP - Profil de base complete ?
  /// Utilise pour les parcours essentiels du profil.
  /// -------------------------
  bool get isMvpProfileComplete {
    switch (role) {
      case 'joueur':
        return nom.isNotEmpty &&
            (position?.isNotEmpty ?? false) &&
            (team?.isNotEmpty ?? false);

      case 'club':
        return nom.isNotEmpty &&
            (nomClub?.isNotEmpty ?? false) &&
            (ligue?.isNotEmpty ?? false);

      case 'recruteur':
      case 'agent':
        return nom.isNotEmpty && (entreprise?.isNotEmpty ?? false);

      default:
        return nom.isNotEmpty;
    }
  }

  /// -------------------------
  /// Profil avance - Presence de donnees professionnelles
  /// Utilise pour les vues enrichies et le dossier scout.
  /// -------------------------
  bool get hasAdvancedProfile {
    switch (role) {
      case 'joueur':
        return playerProfile != null && playerProfile!.isNotEmpty;

      case 'club':
        return clubProfile != null && clubProfile!.isNotEmpty;

      case 'recruteur':
      case 'agent':
        return agentProfile != null && agentProfile!.isNotEmpty;

      default:
        return false;
    }
  }

  /// -------------------------
  /// Joueur - Dossier scout exploitable ?
  /// Utilise par les recruteurs et les parcours avances.
  /// -------------------------
  bool get hasScoutReadyProfile {
    if (!isPlayer || playerProfile == null) return false;

    final p = playerProfile!;

    // Physical (nested)
    final physical = (p['physical'] is Map)
        ? Map<String, dynamic>.from(p['physical'] as Map)
        : <String, dynamic>{};

    final hasPhysical = physical['heightCm'] != null ||
        physical['weightKg'] != null ||
        physical['strongFoot'] != null;

    // Positions
    final positions = p['positions'];
    final hasPosition = (positions is List && positions.isNotEmpty) ||
        (position?.isNotEmpty ?? false);

    // Skills
    final skills = p['skills'];
    final hasSkills = skills is List && skills.isNotEmpty;

    // Stats
    final stats = p['stats'];
    final hasStats = stats is Map && stats.isNotEmpty;

    // Evidence
    final hasEvidence = (videosPubliees?.isNotEmpty ?? false) || cvUrl != null;

    // Scout-ready
    return (hasPhysical || hasSkills) && hasPosition && hasStats && hasEvidence;
  }

  /// -------------------------
  /// UI – Afficher bloc "Profil avancé" ?
  /// -------------------------
  bool get shouldShowAdvancedSection {
    if (isPlayer) return true;
    if (isClub) return true;
    if (isRecruiter) return true;
    return false;
  }

  /// -------------------------
  /// UI – Afficher CTA "Compléter profil avancé" ?
  /// -------------------------
  bool get shouldPromptAdvancedCompletion {
    return isMvpProfileComplete && !hasAdvancedProfile;
  }

  /// -------------------------
  /// Indicateur simple (badge / chip)
  /// -------------------------
  String get profileLevelLabel {
    if (hasScoutReadyProfile) return 'Profil Élite';
    if (hasAdvancedProfile) return 'Profil Avancé';
    if (isMvpProfileComplete) return 'Profil Vérifié';
    return 'Profil Basique';
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  static String? _normalizeBlockMode(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    if (normalized == 'temporary' || normalized == 'permanent') {
      return normalized;
    }

    return null;
  }
}
