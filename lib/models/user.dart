import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/models/video.dart';
import 'package:show_talent/models/offre.dart'; 
import 'package:show_talent/models/event.dart';

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
  String? bio;  // Ajout pour tous les utilisateurs
  String? position;  // Pour les joueurs
  String? clubActuel;  // Pour les joueurs
  int? nombreDeMatchs;  // Pour les joueurs
  int? buts;  // Pour les joueurs
  int? assistances;  // Pour les joueurs
  List<Video>? videosPubliees;  // Pour les joueurs
  Map<String, double>? performances;  // Pour les joueurs

  String? nomClub;  // Pour les clubs
  String? ligue;  // Pour les clubs
  List<Offre>? offrePubliees;  // Pour les clubs/recruteurs
  List<Event>? eventPublies;  // Pour les clubs/recruteurs

  String? entreprise;  // Pour les recruteurs
  int? nombreDeRecrutements;  // Pour les recruteurs

  String? team;  // Ajout pour joueurs et coachs (nom de l'équipe actuelle)
  List<AppUser>? joueursSuivis;  // Pour les fans
  List<AppUser>? clubsSuivis;  // Pour les fans
  List<Video>? videosLikees;  // Pour les fans

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
  });

  // Convertir les données Firestore en AppUser
  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      uid: map['uid'] ?? '', // Utiliser une valeur par défaut si null
      nom: map['nom'] ?? 'Nom inconnu', // Valeur par défaut
      email: map['email'] ?? 'Email inconnu', // Valeur par défaut
      role: map['role'] ?? 'Utilisateur', // Valeur par défaut
      photoProfil: map['photoProfil'] ?? '', // Valeur par défaut
      estActif: map['estActif'] ?? true,
      followers: map['followers'] ?? 0,
      followings: map['followings'] ?? 0,
      dateInscription: (map['dateInscription'] as Timestamp?)?.toDate() ?? DateTime.now(), // Valeur par défaut
      dernierLogin: (map['dernierLogin'] as Timestamp?)?.toDate() ?? DateTime.now(), // Valeur par défaut
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
    };
  }
}
