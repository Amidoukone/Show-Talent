import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/membership.dart';
import 'package:adfoot/models/offre.dart';
import 'package:adfoot/models/org_football_profile.dart';
import 'package:adfoot/models/player_football_profile.dart';
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
  /// Les faits footballistiques, tels qu'un recruteur les filtre.
  ///
  /// Stockes a plat sur le document (`positionCodes`, `strongFoot`,
  /// `birthYear`…) parce qu'une requete Firestore n'indexe pas utilement un
  /// champ enfoui dans une map. Parse a la source et conserve : le recalculer
  /// depuis [toMap] le viderait, puisque [toMap] ne reserialise que les champs
  /// que le titulaire a le droit d'ecrire. Voir [PlayerFootballProfile].
  PlayerFootballProfile football;

  /// Ce que le club declare, type. Voir [ClubFootballProfile].
  ClubFootballProfile club;

  /// Ce que l'agent ou le recruteur declare, type.
  /// Voir [AgentFootballProfile].
  AgentFootballProfile agent;

  /// Ancien profil joueur en texte libre, remplace par [football].
  ///
  /// Conserve pour ne pas perdre le document d'un compte qui en porte encore
  /// un, mais plus alimente ni lu par aucune surface.
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

  // =========================
  // Acceptation des CGU
  // =========================

  /// Version des conditions generales acceptee par ce compte, ou null.
  ///
  /// Deliberement absente de [toEmbeddedMap] : cette copie embarquee est
  /// recopiee telle quelle dans les candidatures et les inscriptions aux
  /// evenements, et les regles Firestore comparent ces lignes par valeur pour
  /// empecher un joueur d'effacer celle d'un autre. Y ajouter un champ ferait
  /// diverger la ligne re-serialisee de celle qui est stockee, et une
  /// candidature parfaitement legitime serait refusee.
  String? acceptedTermsVersion;

  /// Instant de cette acceptation, tel que pose par le serveur.
  DateTime? acceptedTermsAt;

  // =========================
  // Droits enregistres par l'administration
  // =========================

  /// Ce que l'administration a enregistre pour ce compte.
  ///
  /// Lecture seule cote client : `membership` est absent de la liste blanche
  /// `canUpdateOwnProfile` dans firestore.rules, donc seul le callable admin
  /// peut l'ecrire. Absent des maps embarquees pour la meme raison que
  /// l'acceptation des CGU — voir [acceptedTermsVersion].
  Membership membership;

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
    this.football = const PlayerFootballProfile(),
    this.club = const ClubFootballProfile(),
    this.agent = const AgentFootballProfile(),
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

    // CGU
    this.acceptedTermsVersion,
    this.acceptedTermsAt,

    // Droits
    this.membership = Membership.none,
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
      football: PlayerFootballProfile.fromUserMap(map),
      club: ClubFootballProfile.fromUserMap(map),
      agent: AgentFootballProfile.fromUserMap(map),
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
      acceptedTermsVersion: _normalizeNullableString(
        map['acceptedTermsVersion'],
      ),
      acceptedTermsAt: _parseNullableDate(map['acceptedTermsAt']),
      membership: Membership.fromMap(map['membership']),
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
      // Uniquement ce que le titulaire a le droit d'ecrire :
      // `saveUserProfile` pousse cette map telle quelle, et
      // `birthYear`/`isSearchable` sont derives cote serveur.
      ...football.toPatch(),
      ...club.toPatch(),
      ...agent.toPatch(),
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

      // Droits — jamais ecrits par le client, la regle Firestore les refuse.
      'membership': membership.isRecorded ? membership.toMap() : null,

      // CGU
      'acceptedTermsVersion': acceptedTermsVersion,
      'acceptedTermsAt': acceptedTermsAt != null
          ? Timestamp.fromDate(acceptedTermsAt!)
          : null,
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

  /// Vrai quand le compte doit porter le badge « joueur agence ».
  ///
  /// Le callable admin accepte un dossier `adfoot` sur n'importe quel compte
  /// suivi par l'administration, club ou agent compris ; le badge, lui, parle
  /// d'un joueur porte par l'agence et reste donc aux joueurs. Un dossier
  /// echu ne l'affiche pas non plus — voir [Membership.isAgencyPlayerAt].
  bool isAgencyPlayerAt(DateTime now) =>
      isPlayer && membership.isAgencyPlayerAt(now);

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
      // Le profil de base, et rien de footballistique : le poste est devenu
      // un fait avance (voir [football]). L'exiger ici rendrait « Profil
      // complet » inatteignable -- tout joueur qui a un poste est deja
      // « avance » -- et eteindrait du meme coup l'invitation a completer le
      // dossier, qui ne s'affiche que sur un profil complet sans dossier.
      case 'joueur':
        return nom.isNotEmpty &&
            ((team?.trim().isNotEmpty ?? false) ||
                (clubActuel?.trim().isNotEmpty ?? false));

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
        // Les faits footballistiques vivent a plat sur le document depuis la
        // refonte (voir [football]) ; `playerProfile` n'est plus alimente.
        return football.isNotEmpty;

      case 'club':
        return club.isNotEmpty;

      case 'recruteur':
      case 'agent':
        return agent.isNotEmpty;

      default:
        return false;
    }
  }

  /// -------------------------
  /// Joueur - Dossier scout exploitable ?
  /// Utilise par les recruteurs et les parcours avances.
  /// -------------------------
  /// Ce qu'il manque au dossier scout, dans l'ordre ou un recruteur le demande.
  ///
  /// Une seule liste, et [hasScoutReadyProfile] en decoule. Deux declarations
  /// -- l'une pour decider, l'autre pour expliquer -- c'est la garantie qu'un
  /// jour l'ecran reclame un champ que la regle n'exige plus, ou se taise sur
  /// un champ qu'elle exige. Ajouter une exigence, c'est ajouter une entree
  /// ici, et l'ecran suit tout seul.
  ///
  /// Vide pour un compte qui n'est pas un joueur : la notion ne s'y applique
  /// pas, et c'est [hasScoutReadyProfile] qui garde ce cas.
  List<String> get missingScoutRequirements {
    if (!isPlayer) return const <String>[];

    final profile = football;
    final missing = <String>[];

    // Le pays d'abord : c'est, avec l'age, ce qu'un club demande avant meme
    // de regarder une video.
    if (country?.trim().isEmpty ?? true) missing.add('Pays');

    // L'age ensuite, parce que sans lui le serveur ne rend pas ce dossier
    // trouvable : `computeIsSearchable` refuse un `birthYear` nul
    // (functions/src/user_search_fields.ts). L'omettre ici annoncait un
    // « Dossier scout pret » a un joueur qu'aucune recherche de recruteur ne
    // remontait -- le pire des cas, puisque rien ne le lui disait.
    //
    // Reclame par le nom du champ que le joueur remplit (« Date de
    // naissance », profil de base) et non par celui de l'annee derivee, qui
    // n'est editable sur aucun ecran.
    if (profile.birthYear == null) missing.add('Date de naissance');

    if (profile.nationalities.isEmpty) missing.add('Nationalité');
    if (profile.positions.isEmpty) missing.add('Poste');
    if (profile.strongFoot == null) missing.add('Pied fort');
    if (profile.heightCm == null) missing.add('Taille');
    if (profile.contractStatus == null) {
      missing.add('Statut contractuel');
    }
    if (profile.currentClubLevel == null) {
      missing.add('Niveau du club actuel');
    }
    if (profile.currentSeason == null) {
      missing.add('Statistiques de la saison en cours');
    }

    final hasEvidence =
        (videosPubliees?.isNotEmpty ?? false) ||
        (cvUrl?.trim().isNotEmpty ?? false);
    if (!hasEvidence) missing.add('Une vidéo publiée ou un CV');

    return List<String>.unmodifiable(missing);
  }

  /// Dossier exploitable : il ne manque plus rien.
  ///
  /// Le pays n'est pas un champ de confort : il decide de la voie d'obtention
  /// d'un permis de travail, et c'est l'une des deux questions qu'un club
  /// europeen pose avant meme de regarder une video. Il vit sur le compte et
  /// non dans `playerProfile` -- champ transverse, saisi dans le profil de
  /// base.
  ///
  /// L'autre question, l'age, est exigee elle aussi, mais via `birthYear` et
  /// non via `birthDate`. La distinction est ce qui rend le jugement lisible
  /// par tout le monde : `birthDate` vit dans `users/{uid}/private/contact` et
  /// n'atteint que le titulaire (`includePrivateFields: uid ==
  /// currentAuthUid`), donc l'exiger rendait ce getter dependant de qui
  /// regarde -- le joueur voyait « Elite » pendant qu'un recruteur voyait
  /// « partiel » sur le meme dossier. `birthYear` est derive cote serveur et
  /// pose en clair sur le document public : annee seule, de quoi filtrer une
  /// tranche d'age sans exposer une date de naissance complete. Les deux
  /// lecteurs le recoivent, donc le verdict ne bouge plus avec le lecteur.
  ///
  /// Il n'est dans aucune liste blanche d'ecriture client
  /// (`canUpdateOwnProfile`, firestore.rules) : seul le trigger
  /// `deriveUserSearchFields` l'ecrit. Un joueur ne peut donc pas s'attribuer
  /// une visibilite qu'il n'a pas.
  ///
  /// Derive de [missingScoutRequirements] plutot que de reevaluer les memes
  /// conditions : c'est la seule facon que l'ecran qui explique et la regle
  /// qui decide ne se contredisent jamais.
  bool get hasScoutReadyProfile =>
      isPlayer && missingScoutRequirements.isEmpty;

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
