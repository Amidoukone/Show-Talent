import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/models/event.dart';
import 'package:show_talent/models/offre.dart';
import 'package:show_talent/models/video.dart';

class AppUser {
  String uid;
  String nom;
  String email;
  String role;
  String photoProfil;
  bool estActif;
  int followers;
  int followings;
  DateTime dateInscription;
  DateTime dernierLogin;

  // Informations spécifiques à chaque rôle
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

  List<String> followersList; // Liste des UID des followers
  List<String> followingsList; // Liste des UID des followings

  AppUser({
    required this.uid,
    required this.nom,
    required this.email,
    required this.role,
    required this.photoProfil,
    required this.estActif,
    required this.followers,
    required this.followings,
    required this.dateInscription,
    required this.dernierLogin,
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
    required this.followersList,
    required this.followingsList,
  });

  // Méthodes pour suivre et se désabonner
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

  // Convertir les données Firestore en AppUser
  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      uid: map['uid'] ?? '',
      nom: map['nom'] ?? 'Nom inconnu',
      email: map['email'] ?? 'Email inconnu',
      role: map['role'] ?? 'Utilisateur',
      photoProfil: map['photoProfil'] ?? '',
      estActif: map['estActif'] ?? true,
      followers: map['followers'] is int ? map['followers'] : 0,
      followings: map['followings'] is int ? map['followings'] : 0,
      dateInscription: (map['dateInscription'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dernierLogin: (map['dernierLogin'] as Timestamp?)?.toDate() ?? DateTime.now(),
      bio: map['bio'],
      position: map['position'],
      clubActuel: map['clubActuel'],
      nombreDeMatchs: map['nombreDeMatchs'],
      buts: map['buts'],
      assistances: map['assistances'],
      videosPubliees: map['videosPubliees'] != null
          ? List<Video>.from(map['videosPubliees'].map((video) => Video.fromMap(video)))
          : [],
      performances: map['performances'] != null
          ? Map<String, double>.from(map['performances'])
          : {},
      nomClub: map['nomClub'],
      ligue: map['ligue'],
      offrePubliees: map['offrePubliees'] != null
          ? List<Offre>.from(map['offrePubliees'].map((offre) => Offre.fromMap(offre)))
          : [],
      eventPublies: map['eventPublies'] != null
          ? List<Event>.from(map['eventPublies'].map((event) => Event.fromMap(event)))
          : [],
      entreprise: map['entreprise'],
      nombreDeRecrutements: map['nombreDeRecrutements'],
      team: map['team'],
      joueursSuivis: map['joueursSuivis'] != null
          ? List<AppUser>.from(map['joueursSuivis'].map((joueur) => AppUser.fromMap(joueur)))
          : [],
      clubsSuivis: map['clubsSuivis'] != null
          ? List<AppUser>.from(map['clubsSuivis'].map((club) => AppUser.fromMap(club)))
          : [],
      videosLikees: map['videosLikees'] != null
          ? List<Video>.from(map['videosLikees'].map((video) => Video.fromMap(video)))
          : [],
      followersList: List<String>.from(map['followersList'] ?? []),
      followingsList: List<String>.from(map['followingsList'] ?? []),
    );
  }

  // Convertir AppUser en Map pour Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'nom': nom,
      'email': email,
      'role': role,
      'photoProfil': photoProfil,
      'estActif': estActif,
      'followers': followers,
      'followings': followings,
      'dateInscription': dateInscription,
      'dernierLogin': dernierLogin,
      'bio': bio,
      'position': position,
      'clubActuel': clubActuel,
      'nombreDeMatchs': nombreDeMatchs,
      'buts': buts,
      'assistances': assistances,
      'videosPubliees': videosPubliees != null
          ? videosPubliees!.map((video) => video.toMap()).toList()
          : [],
      'performances': performances ?? {},
      'nomClub': nomClub,
      'ligue': ligue,
      'offrePubliees': offrePubliees != null
          ? offrePubliees!.map((offre) => offre.toMap()).toList()
          : [],
      'eventPublies': eventPublies != null
          ? eventPublies!.map((event) => event.toMap()).toList()
          : [],
      'entreprise': entreprise,
      'nombreDeRecrutements': nombreDeRecrutements,
      'team': team,
      'joueursSuivis': joueursSuivis != null
          ? joueursSuivis!.map((joueur) => joueur.toMap()).toList()
          : [],
      'clubsSuivis': clubsSuivis != null
          ? clubsSuivis!.map((club) => club.toMap()).toList()
          : [],
      'videosLikees': videosLikees != null
          ? videosLikees!.map((video) => video.toMap()).toList()
          : [],
      'followersList': followersList,
      'followingsList': followingsList,
    };
  }
}