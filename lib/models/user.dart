import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/offre.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/account_role_policy.dart';

class AppUser {
  // =========================
  // Identite et systeme
  // =========================
  String uid;
  String nom;
  String email;
  String role;
  String photoProfil;
  bool estActif;
  bool authDisabled;
  bool emailVerified;
  bool createdByAdmin;
  int followers;
  int followings;
  DateTime dateInscription;
  DateTime dernierLogin;
  DateTime? emailVerifiedAt;
  String? phone;
  String? authDisabledReason;
  bool profileVerified;
  String profileVerificationStatus;
  DateTime? profileVerifiedAt;
  String? profileVerifiedBy;
  DateTime? profileVerificationUpdatedAt;
  String? profileVerificationUpdatedBy;
  String? profileVerificationNote;
  DateTime? profileVerificationInvalidatedAt;
  String? profileVerificationInvalidatedBy;
  String? profileVerificationInvalidationReason;

  // =========================
  // Champs transverses
  // =========================
  DateTime? birthDate; // age calcule cote client
  String? country;
  String? city;
  String? region;
  List<String>? languages; // ex: ['fr', 'en']
  bool? openToOpportunities;

  // =========================
  // Profil joueur (MVP existant)
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
  // Profil joueur (avance - structure)
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
  // Club / Staff
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
  // Recruteur / Agent
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
  // Organisateur d’événements
  // =========================
  Map<String, dynamic>? eventOrganizerProfile;

  // =========================
  // Social et contenus
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
  // Documents
  // =========================
  String? cvUrl;

  AppUser({
    required this.uid,
    required this.nom,
    required this.email,
    required this.role,
    required this.photoProfil,
    required this.estActif,
    this.authDisabled = false,
    required this.emailVerified,
    this.createdByAdmin = false,
    required this.followers,
    required this.followings,
    required this.dateInscription,
    required this.dernierLogin,
    this.emailVerifiedAt,
    this.phone,
    this.authDisabledReason,
    this.profileVerified = false,
    this.profileVerificationStatus = 'unverified',
    this.profileVerifiedAt,
    this.profileVerifiedBy,
    this.profileVerificationUpdatedAt,
    this.profileVerificationUpdatedBy,
    this.profileVerificationNote,
    this.profileVerificationInvalidatedAt,
    this.profileVerificationInvalidatedBy,
    this.profileVerificationInvalidationReason,

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

    // Avances par role
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
  // Parsing Firestore SAFE
  // =========================
  factory AppUser.fromMap(
    Map<String, dynamic> map, {
    Map<String, dynamic>? privateContact,
  }) {
    final merged = privateContact == null
        ? map
        : <String, dynamic>{...map, ...privateContact};
    return AppUser._fromMap(merged, parseNestedCollections: true);
  }

  factory AppUser.fromEmbeddedMap(Map<String, dynamic> map) {
    return AppUser._fromMap(map, parseNestedCollections: false);
  }

  static AppUser _fromMap(
    Map<String, dynamic> map, {
    required bool parseNestedCollections,
  }) {
    Map<String, dynamic>? safeMap(dynamic v) {
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    List<T>? safeList<T>(dynamic v) {
      if (v is List) return v.cast<T>();
      return null;
    }

    final normalizedRole = normalizeUserRole(map['role']?.toString());
    final profileVerified = map['profileVerified'] == true;

    return AppUser(
      uid: map['uid']?.toString() ?? '',
      nom: map['nom']?.toString() ?? 'Nom inconnu',
      email: map['email']?.toString() ?? '',
      role: normalizedRole.isEmpty ? 'utilisateur' : normalizedRole,
      photoProfil: map['photoProfil']?.toString() ?? '',
      estActif: _toBool(map['estActif'], true),
      authDisabled: map['authDisabled'] == true,
      emailVerified: _toBool(map['emailVerified'], false),
      createdByAdmin: _toBool(map['createdByAdmin'], false),
      emailVerifiedAt: _parseNullableDate(map['emailVerifiedAt']),
      followers: _toInt(map['followers'], 0),
      followings: _toInt(map['followings'], 0),
      dateInscription: _parseDate(map['dateInscription'], DateTime.now()),
      dernierLogin: _parseDate(map['dernierLogin'], DateTime.now()),
      phone: map['phone']?.toString(),
      authDisabledReason: map['authDisabledReason']?.toString(),
      profileVerified: profileVerified,
      profileVerificationStatus: _normalizeProfileVerificationStatus(
        map['profileVerificationStatus'],
        verified: profileVerified,
      ),
      profileVerifiedAt: _parseNullableDate(map['profileVerifiedAt']),
      profileVerifiedBy: _normalizeNullableString(map['profileVerifiedBy']),
      profileVerificationUpdatedAt: _parseNullableDate(
        map['profileVerificationUpdatedAt'],
      ),
      profileVerificationUpdatedBy: _normalizeNullableString(
        map['profileVerificationUpdatedBy'],
      ),
      profileVerificationNote: _normalizeNullableString(
        map['profileVerificationNote'],
      ),
      profileVerificationInvalidatedAt: _parseNullableDate(
        map['profileVerificationInvalidatedAt'],
      ),
      profileVerificationInvalidatedBy: _normalizeNullableString(
        map['profileVerificationInvalidatedBy'],
      ),
      profileVerificationInvalidationReason: _normalizeNullableString(
        map['profileVerificationInvalidationReason'],
      ),

      // Transverses
      birthDate: _parseNullableDate(map['birthDate']),
      country: map['country']?.toString(),
      city: map['city']?.toString(),
      region: map['region']?.toString(),
      languages: map['languages'] is List
          ? List<String>.from(
              (map['languages'] as List).map((e) => e.toString()),
            )
          : null,
      openToOpportunities: _toNullableBool(map['openToOpportunities']),

      // Joueur MVP
      bio: map['bio']?.toString(),
      position: map['position']?.toString(),
      clubActuel: map['clubActuel']?.toString(),
      nombreDeMatchs: _toNullableInt(map['nombreDeMatchs']),
      buts: _toNullableInt(map['buts']),
      assistances: _toNullableInt(map['assistances']),

      videosPubliees: parseNestedCollections && map['videosPubliees'] is List
          ? (map['videosPubliees'] as List)
                .whereType<Map>()
                .map((v) => Video.fromMap(Map<String, dynamic>.from(v)))
                .toList()
          : null,

      performances: map['performances'] is Map
          ? Map<String, double>.fromEntries(
              (map['performances'] as Map).entries
                  .map((entry) {
                    final value = _toNullableDouble(entry.value);
                    return value == null
                        ? null
                        : MapEntry(entry.key.toString(), value);
                  })
                  .whereType<MapEntry<String, double>>(),
            )
          : null,

      // Avances
      playerProfile: safeMap(map['playerProfile']),
      clubProfile: safeMap(map['clubProfile']),
      agentProfile: safeMap(map['agentProfile']),
      eventOrganizerProfile: safeMap(map['eventOrganizerProfile']),

      // Club / recruteur
      nomClub: map['nomClub']?.toString(),
      ligue: map['ligue']?.toString(),

      offrePubliees: parseNestedCollections && map['offrePubliees'] is List
          ? (map['offrePubliees'] as List)
                .whereType<Map>()
                .map((v) => Offre.fromMap(Map<String, dynamic>.from(v)))
                .toList()
          : null,

      eventPublies: parseNestedCollections && map['eventPublies'] is List
          ? (map['eventPublies'] as List)
                .whereType<Map>()
                .map((v) => Event.fromMap(Map<String, dynamic>.from(v)))
                .toList()
          : null,

      entreprise: map['entreprise']?.toString(),
      nombreDeRecrutements: _toNullableInt(map['nombreDeRecrutements']),

      // Social
      team: map['team']?.toString(),

      joueursSuivis: parseNestedCollections && map['joueursSuivis'] is List
          ? (map['joueursSuivis'] as List)
                .whereType<Map>()
                .map(
                  (j) => AppUser.fromEmbeddedMap(
                    Map<String, dynamic>.from(j),
                  ),
                )
                .toList()
          : null,

      clubsSuivis: parseNestedCollections && map['clubsSuivis'] is List
          ? (map['clubsSuivis'] as List)
                .whereType<Map>()
                .map(
                  (c) => AppUser.fromEmbeddedMap(
                    Map<String, dynamic>.from(c),
                  ),
                )
                .toList()
          : null,

      videosLikees: parseNestedCollections && map['videosLikees'] is List
          ? (map['videosLikees'] as List)
                .whereType<Map>()
                .map((v) => Video.fromMap(Map<String, dynamic>.from(v)))
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
      profilePublic: _toBool(map['profilePublic'], true),
      allowMessages: _toBool(map['allowMessages'], true),
    );
  }

  // =========================
  // Firestore export SAFE
  // =========================
  Map<String, dynamic> toEmbeddedMap() {
    // email/phone are intentionally excluded: this map gets embedded into
    // documents other users can read (offer candidates, event participants,
    // follow lists), and those two fields now live in
    // users/{uid}/private/contact specifically so third parties can't see
    // them.
    return {
      'uid': uid,
      'nom': nom,
      'role': role,
      'photoProfil': photoProfil,
      'estActif': estActif,
      'authDisabled': authDisabled,
      'emailVerified': emailVerified,
      'createdByAdmin': createdByAdmin,
      'profileVerified': profileVerified,
      'profileVerificationStatus': profileVerificationStatus,
      'nomClub': nomClub,
      'ligue': ligue,
      'entreprise': entreprise,
      'team': team,
      'profilePublic': profilePublic,
      'allowMessages': allowMessages,
    };
  }

  /// Fields for the users/{uid} doc. phone, birthDate, cvUrl, email and
  /// authDisabledReason are intentionally absent — they live in
  /// users/{uid}/private/contact (see [toPrivateContactMap]) and
  /// profileVerificationNote lives in users/{uid}/private/adminNotes
  /// (admin-write only, not exposed here at all).
  Map<String, dynamic> toMap() {
    return {
      ...toEmbeddedMap(),
      'emailVerifiedAt': emailVerifiedAt != null
          ? Timestamp.fromDate(emailVerifiedAt!)
          : null,
      'followers': followers,
      'followings': followings,
      'dateInscription': Timestamp.fromDate(dateInscription),
      'dernierLogin': Timestamp.fromDate(dernierLogin),
      'profileVerifiedAt': profileVerifiedAt != null
          ? Timestamp.fromDate(profileVerifiedAt!)
          : null,
      'profileVerifiedBy': profileVerifiedBy,
      'profileVerificationUpdatedAt': profileVerificationUpdatedAt != null
          ? Timestamp.fromDate(profileVerificationUpdatedAt!)
          : null,
      'profileVerificationUpdatedBy': profileVerificationUpdatedBy,
      'profileVerificationInvalidatedAt':
          profileVerificationInvalidatedAt != null
          ? Timestamp.fromDate(profileVerificationInvalidatedAt!)
          : null,
      'profileVerificationInvalidatedBy': profileVerificationInvalidatedBy,
      'profileVerificationInvalidationReason':
          profileVerificationInvalidationReason,

      // Transverses
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

      // Avances
      'playerProfile': playerProfile,
      'clubProfile': clubProfile,
      'agentProfile': agentProfile,
      'eventOrganizerProfile': eventOrganizerProfile,

      // Club / recruteur
      'offrePubliees': offrePubliees?.map((o) => o.toMap()).toList(),
      'eventPublies': eventPublies?.map((e) => e.toMap()).toList(),
      'nombreDeRecrutements': nombreDeRecrutements,

      // Social
      'joueursSuivis': joueursSuivis?.map((j) => j.toEmbeddedMap()).toList(),
      'clubsSuivis': clubsSuivis?.map((c) => c.toEmbeddedMap()).toList(),
      'videosLikees': videosLikees?.map((v) => v.toMap()).toList(),
      'followersList': followersList,
      'followingsList': followingsList,

      // Docs — cvUrl stays on this doc on purpose: it's meant to be
      // visible to third parties once profilePublic is true, same as the
      // Storage rule already gates the actual PDF (unlike phone/birthDate,
      // which never had a legitimate third-party audience).
      'cvUrl': cvUrl,
    };
  }

  /// Fields for users/{uid}/private/contact — owner/admin read-only doc.
  /// email and authDisabledReason in that same doc are admin/Cloud-Function
  /// managed and are never written from this client-side map.
  Map<String, dynamic> toPrivateContactMap() {
    return {
      'phone': phone,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
    };
  }

  // =========================
  // Age calcule (safe)
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

  /// Role helpers
  bool get isPlayer => role == 'joueur';
  bool get isClub => role == 'club';
  bool get isAgent => role == 'agent';
  bool get isRecruiter => role == 'recruteur' || role == 'agent';
  bool get isCoach => role == 'coach';
  bool get isFan => role == 'fan';
  bool get canPublishOpportunities => isOpportunityPublisherRole(role);

  bool get isEffectivelyActiveAccount => !authDisabled && emailVerified;
  bool get isProfileTrusted => profileVerified && isEffectivelyActiveAccount;
  bool get profileVerificationNeedsReview =>
      !profileVerified && profileVerificationStatus == 'pending';

  String get profileTrustLabel {
    if (isProfileTrusted) return 'Vérifié par Adfoot';
    if (profileVerified && !isEffectivelyActiveAccount) {
      return 'Certification suspendue';
    }
    if (profileVerificationNeedsReview) return 'A revalider par Adfoot';
    return 'Non certifié';
  }

  String get profileVerificationStatusLabel {
    switch (profileVerificationStatus) {
      case 'verified':
        return 'Vérifié par admin';
      case 'rejected':
        return 'Vérification refusée';
      case 'pending':
        return 'Vérification en attente';
      case 'unverified':
      default:
        return 'Non vérifié';
    }
  }

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
        return nom.isNotEmpty && (ligue?.isNotEmpty ?? false);

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
        return _hasMeaningfulProfileValue(playerProfile);

      case 'club':
        return _hasMeaningfulProfileValue(clubProfile);

      case 'recruteur':
      case 'agent':
        return _hasMeaningfulProfileValue(agentProfile);

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

    final hasPhysical =
        physical['heightCm'] != null ||
        physical['weightKg'] != null ||
        physical['strongFoot'] != null;

    // Positions
    final positions = p['positions'];
    final hasPosition = positions is List && positions.isNotEmpty;

    // Skills
    final skills = p['skills'];
    final hasSkills = skills is List && skills.isNotEmpty;

    // Stats
    final stats = p['stats'];
    final hasStats = stats is Map && stats.isNotEmpty;

    // Evidence
    final hasEvidence =
        (videosPubliees?.isNotEmpty ?? false) ||
        (cvUrl?.trim().isNotEmpty ?? false);

    // Scout-ready
    return (hasPhysical || hasSkills) && hasPosition && hasStats && hasEvidence;
  }

  /// -------------------------
  /// UI - Afficher bloc "Profil avance" ?
  /// -------------------------
  bool get shouldShowAdvancedSection {
    if (isPlayer) return true;
    if (isClub) return true;
    if (isRecruiter) return true;
    return false;
  }

  /// -------------------------
  /// UI - Afficher CTA "Completer profil avance" ?
  /// -------------------------
  bool get shouldPromptAdvancedCompletion {
    return isMvpProfileComplete && !hasAdvancedProfile;
  }

  static bool _hasMeaningfulProfileValue(dynamic value) {
    if (value == null) {
      return false;
    }
    if (value is String) {
      return value.trim().isNotEmpty;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return true;
    }
    if (value is List) {
      return value.any(_hasMeaningfulProfileValue);
    }
    if (value is Map) {
      return value.values.any(_hasMeaningfulProfileValue);
    }
    return true;
  }

  /// -------------------------
  /// Indicateur simple (badge / chip)
  /// -------------------------
  String get profileLevelLabel {
    if (hasScoutReadyProfile) return 'Profil Élite';
    if (hasAdvancedProfile) return 'Profil avancé';
    if (isMvpProfileComplete) return 'Profil complet';
    return 'Profil basique';
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static DateTime _parseDate(dynamic value, DateTime fallback) {
    return _parseNullableDate(value) ?? fallback;
  }

  static bool _toBool(dynamic value, bool fallback) {
    if (value is bool) return value;
    return fallback;
  }

  static bool? _toNullableBool(dynamic value) {
    return value is bool ? value : null;
  }

  static int _toInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String? _normalizeNullableString(dynamic value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _normalizeProfileVerificationStatus(
    dynamic value, {
    required bool verified,
  }) {
    final normalized = value?.toString().trim().toLowerCase();
    const supportedStatuses = {'verified', 'unverified', 'pending', 'rejected'};

    if (normalized != null && supportedStatuses.contains(normalized)) {
      return normalized;
    }

    return verified ? 'verified' : 'unverified';
  }
}
