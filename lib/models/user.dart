class AppUser {
  String uid;
  String name;
  String email;
  String role; // joueur, club, recruteur, fan, coach
  String profilePhoto;
  List<String> followers;
  List<String> following;

  // Informations spécifiques à chaque rôle
  String? team; // Pour joueur ou coach
  String? clubName; // Pour club
  String? bio; // Pour tous les utilisateurs (biographie)
  List<String>? videos; // Pour les utilisateurs qui partagent des vidéos

  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.profilePhoto,
    required this.followers,
    required this.following,
    this.team,
    this.clubName,
    this.bio,
    this.videos,
  });

  // Méthode pour convertir les données Firestore en AppUser
  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      uid: map['uid'],
      name: map['name'],
      email: map['email'],
      role: map['role'],
      profilePhoto: map['profilePhoto'],
      followers: List<String>.from(map['followers']),
      following: List<String>.from(map['following']),
      team: map['team'], // Spécifique à joueur/coach
      clubName: map['clubName'], // Spécifique à club
      bio: map['bio'], // Biographie
      videos: List<String>.from(map['videos'] ?? []), // Liste des vidéos
    );
  }

  // Méthode pour convertir AppUser en données Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': role,
      'profilePhoto': profilePhoto,
      'followers': followers,
      'following': following,
      'team': team,
      'clubName': clubName,
      'bio': bio,
      'videos': videos ?? [],
    };
  }
}
