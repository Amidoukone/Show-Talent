import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/offre.dart';
import 'package:adfoot/models/video.dart';

class AppUser {
  String uid;
  String nom;
  String email;
  String role;
  String photoProfil;
  bool estActif;
  bool estBloque;
  bool emailVerified;
  int followers;
  int followings;
  DateTime dateInscription;
  DateTime dernierLogin;
  DateTime? emailVerifiedAt; // 🆕 Nouveau champ
  String? phone;

  String? bio;
  String? position;
  String? clubActuel;
  int? nombreDeMatchs;
  int? buts;
  int? assistances;
  List<Video>? videosPubliees;
  Map<String, double>? performances;

  String? nomClub;
  String? ligue;
  List<Offre>? offrePubliees;
  List<Event>? eventPublies;

  String? entreprise;
  int? nombreDeRecrutements;

  String? team;
  List<AppUser>? joueursSuivis;
  List<AppUser>? clubsSuivis;
  List<Video>? videosLikees;

  List<String> followersList;
  List<String> followingsList;

  String? cvUrl;

  AppUser({
    required this.uid,
    required this.nom,
    required this.email,
    required this.role,
    required this.photoProfil,
    required this.estActif,
    required this.estBloque,
    required this.emailVerified,
    required this.followers,
    required this.followings,
    required this.dateInscription,
    required this.dernierLogin,
    this.emailVerifiedAt,
    this.phone,
    this.bio,
    this.position,
    this.clubActuel,
    this.nombreDeMatchs,
    this.buts,
    this.assistances,
    this.videosPubliees,
    this.performances,
    this.nomClub,
    this.ligue,
    this.offrePubliees,
    this.eventPublies,
    this.entreprise,
    this.nombreDeRecrutements,
    this.team,
    this.joueursSuivis,
    this.clubsSuivis,
    this.videosLikees,
    this.cvUrl,
    required this.followersList,
    required this.followingsList,
  });

  void follow(String uid) {
    if (!followingsList.contains(uid)) {
      followingsList.add(uid);
      followings++;
    }
  }

  void unfollow(String uid) {
    if (followingsList.contains(uid)) {
      followingsList.remove(uid);
      followings--;
    }
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      uid: map['uid'] ?? '',
      nom: map['nom'] ?? 'Nom inconnu',
      email: map['email'] ?? '',
      role: map['role'] ?? 'Utilisateur',
      photoProfil: map['photoProfil'] ?? '',
      estActif: map['estActif'] ?? false,
      estBloque: map['estBloque'] ?? false,
      emailVerified: map['emailVerified'] ?? false,
      emailVerifiedAt: (map['emailVerifiedAt'] as Timestamp?)?.toDate(), // 🆕
      followers: map['followers'] ?? 0,
      followings: map['followings'] ?? 0,
      dateInscription: (map['dateInscription'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dernierLogin: (map['dernierLogin'] as Timestamp?)?.toDate() ?? DateTime.now(),
      phone: map['phone'],
      bio: map['bio'],
      position: map['position'],
      clubActuel: map['clubActuel'],
      nombreDeMatchs: map['nombreDeMatchs'],
      buts: map['buts'],
      assistances: map['assistances'],
      videosPubliees: map['videosPubliees'] != null
          ? List<Video>.from(map['videosPubliees'].map((v) => Video.fromMap(v)))
          : [],
      performances: map['performances'] != null ? Map<String, double>.from(map['performances']) : {},
      nomClub: map['nomClub'],
      ligue: map['ligue'],
      offrePubliees: map['offrePubliees'] != null
          ? List<Offre>.from(map['offrePubliees'].map((v) => Offre.fromMap(v)))
          : [],
      eventPublies: map['eventPublies'] != null
          ? List<Event>.from(map['eventPublies'].map((v) => Event.fromMap(v)))
          : [],
      entreprise: map['entreprise'],
      nombreDeRecrutements: map['nombreDeRecrutements'],
      team: map['team'],
      joueursSuivis: map['joueursSuivis'] != null
          ? List<AppUser>.from(map['joueursSuivis'].map((j) => AppUser.fromMap(j)))
          : [],
      clubsSuivis: map['clubsSuivis'] != null
          ? List<AppUser>.from(map['clubsSuivis'].map((c) => AppUser.fromMap(c)))
          : [],
      videosLikees: map['videosLikees'] != null
          ? List<Video>.from(map['videosLikees'].map((v) => Video.fromMap(v)))
          : [],
      followersList: List<String>.from(map['followersList'] ?? []),
      followingsList: List<String>.from(map['followingsList'] ?? []),
      cvUrl: map['cvUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'nom': nom,
      'email': email,
      'role': role,
      'photoProfil': photoProfil,
      'estActif': estActif,
      'estBloque': estBloque,
      'emailVerified': emailVerified,
      'emailVerifiedAt': emailVerifiedAt != null ? Timestamp.fromDate(emailVerifiedAt!) : null, // 🆕
      'followers': followers,
      'followings': followings,
      'dateInscription': Timestamp.fromDate(dateInscription),
      'dernierLogin': Timestamp.fromDate(dernierLogin),
      'phone': phone,
      'bio': bio,
      'position': position,
      'clubActuel': clubActuel,
      'nombreDeMatchs': nombreDeMatchs,
      'buts': buts,
      'assistances': assistances,
      'videosPubliees': videosPubliees?.map((v) => v.toMap()).toList() ?? [],
      'performances': performances ?? {},
      'nomClub': nomClub,
      'ligue': ligue,
      'offrePubliees': offrePubliees?.map((o) => o.toMap()).toList() ?? [],
      'eventPublies': eventPublies?.map((e) => e.toMap()).toList() ?? [],
      'entreprise': entreprise,
      'nombreDeRecrutements': nombreDeRecrutements,
      'team': team,
      'joueursSuivis': joueursSuivis?.map((j) => j.toMap()).toList() ?? [],
      'clubsSuivis': clubsSuivis?.map((c) => c.toMap()).toList() ?? [],
      'videosLikees': videosLikees?.map((v) => v.toMap()).toList() ?? [],
      'followersList': followersList,
      'followingsList': followingsList,
      'cvUrl': cvUrl,
    };
  }
}
